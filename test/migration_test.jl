
### LP Representation 
#function HousingMarket
import Pkg
Pkg.activate(dirname(@__DIR__))

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
using Agents
using JuMP
import HiGHS

using BenchmarkTools, TimerOutputs

## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_levee.csv")))

### Intialize Model ###
#Define relevant parameters
model_evolve = CHANCE_C.model_step!
no_of_years = 50
perc_growth = 0.01
perc_move = 0.025
house_choice_mode = "flood_mem_utility"
flood_coef = -10.0^5
levee = false
breach = true
slr_scen = "medium" #Select SLR Scenario to use (choice of "low", "medium", and "high")
slr_rate = [3.03e-3,7.878e-3,2.3e-2] #Define SLR Rate of change for each scenario ( list order is "low", "medium", and "high")
breach_null = 0.45 
risk_averse = 0.3 
flood_mem = 10 
fixed_effect = 0

balt_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

tmr = TimerOutput()

#Run Agent Sampler 
function agent_migration(abm::ABM; growth_rate = 0.01, hh_size = 2.7, no_hhs_per_agent = 10)
    abm.tick += 1
    for id in Agents.schedule(abm)
        agent_step!(abm[id], abm)
    end
    @timeit tmr "Input Setup" begin
        ##Set up LP
        #Utility Matrix 
        U = abm.hh_utilities
        n = size(U)[1]
        q = size(U)[2]
        c = size(U)[3]

        #New incoming agents
        new_population = abm.total_population * growth_rate
        total_agents = fld(((new_population / hh_size) + fld(no_hhs_per_agent, 2)), no_hhs_per_agent)
        new_agents = fld(total_agents, c) 

        m  = zeros(c) # Vector of length c
        for k in 1:c
            m[k] = sum([a.n_move for a in allagents(abm) if a isa HHAgent && a.inc_cat == k]) + new_agents
        end

        A = zeros(n,q) # n x q matrix
        for id in filter!(id -> abm[id] isa CHANCE_C.House, collect(Agents.schedule(abm)))
            A[abm[id].bg_id, abm[id].quality] = abm[id].available_units
        end

        #Calculate Penalty Matrix
        Z = zeros(n,q,c)
        for j in 1:q
            for k in 1:c
                Z[:,j,k] = repeat([abs(j-k) * 50000], n)
            end
        end
    end
    @timeit tmr "Model Setup" begin
        model = Model(HiGHS.Optimizer)
        set_silent(model)
        @variable(model, P[1:n,1:q,1:c] .>= 0)

        @constraint(model, [k = 1:c], sum(P[:,:,k]) <= m[k])

        @constraint(model, [i = 1:n, j = 1:q], sum(P[i,j,:]) <= A[i,j])

        @objective(model, Max, sum(P .* U .- Z))
    end

    @timeit tmr "Model Solve" begin
        optimize!(model)
        @assert is_solved_and_feasible(model)
    end
    #return objective_value(model)
    #return value.(P)
    @timeit tmr "Agent Update" begin
        ReloMat = value.(P) 

        for id in filter!(id -> abm[id] isa HHAgent || abm[id] isa House, collect(Agents.schedule(abm)))
            relo_update!(abm[id], ReloMat)
        end
    end
end

step!(balt_abm, 31)
agent_migration(balt_abm)
show(tmr)
reset_timer!(tmr)




#Benchmark function (Run 2x)
b = @benchmarkable AgentMigration(balt_abm) setup=(balt_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)) seconds=10 evals=1

run(b)



balt_abm.tick += 1
for id in Agents.schedule(balt_abm)
    agent_step!(balt_abm[id], balt_abm)
end

U = balt_abm.hh_utilities
n = size(U)[1]
q = size(U)[2]
c = size(U)[3]

new_population = balt_abm.total_population * 0.01
#total_agents = fld(((new_population / hh_size) + fld(no_hhs_per_agent, 2)), no_hhs_per_agent)
total_agents = fld(round(new_population / 2.7), 10)
new_agents = fld(total_agents, c) 

m  = zeros(c) # Vector of length c
for k in 1:c
    m[k] = sum([a.n_move for a in allagents(balt_abm) if a isa HHAgent && a.inc_cat == k]) + new_agents
end

A = zeros(n,q) # n x q matrix
for id in filter!(id -> balt_abm[id] isa CHANCE_C.House, collect(Agents.schedule(balt_abm)))
    A[balt_abm[id].bg_id, balt_abm[id].quality] = balt_abm[id].available_units
end

#Calculate Penalty Matrix
Z = zeros(n,q,c)
for j in 1:q
    for k in 1:c
        if j > k #Higher quality House than income class
            Z[:,j,k] = repeat([abs(j-k) * 100000], n)
        else
            Z[:,j,k] = repeat([abs(j-k) * 50000], n)
        end
        
    end
end

model = Model(HiGHS.Optimizer)
set_silent(model)
@variable(model, P[1:n,1:q,1:c] .>= 0)

@constraint(model, [k = 1:c], sum(P[:,:,k]) <= m[k])

@constraint(model, [i = 1:n, j = 1:q], sum(P[i,j,:]) <= A[i,j])

@objective(model, Max, sum(P .* U .- Z))

optimize!(model)
@assert is_solved_and_feasible(model)

ReloMat = value.(P) 

for id in filter!(id -> balt_abm[id] isa HHAgent || balt_abm[id] isa House, collect(Agents.schedule(balt_abm)))
    relo_update!(balt_abm[id], ReloMat)
end


a_gent = balt_abm[5385]
a_gent.occ_low + a_gent.occ_mid + a_gent.occ_high
a_gent.n_move
a_gent.n_stay

ReloMat[267,:,:]

### LP Representation 
#function HousingMarket

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
using Agents
using JuMP
import HiGHS

using BenchmarkTools

## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/surge_area_baltimore_levee.csv")))

### Intialize Model ###
#Define relevant parameters
model_evolve = CHANCE_C.model_step!
no_of_years = 10
perc_growth = 0.01
perc_move = 0.025
house_choice_mode = "flood_mem_utility"
flood_coef = -10.0^5
levee = false
breach = true
slr_scen = "high" #Select SLR Scenario to use (choice of "low", "medium", and "high")
slr_rate = [3.03e-3,7.878e-3,2.3e-2] #Define SLR Rate of change for each scenario ( list order is "low", "medium", and "high")
breach_null = 0.45 
risk_averse = 0.3 
flood_mem = 10 
fixed_effect = 0

balt_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

#Run Agent Sampler 
function AgentMigration(abm::ABM)
    for id in filter!(id -> abm[id] isa HHAgent, collect(Agents.schedule(abm)))
        agent_step!(abm[id], abm)
    end

    ##Set up LP
    #Utility Matrix 
    U = rand(100000:400000, 1220,3,3)
    n = size(U)[1]
    q = size(U)[2]
    c = size(U)[3]

    m  = zeros(c) # Vector of length c
    for k in 1:c
        m[k] = sum([a.n_move for a in allagents(abm) if a isa HHAgent && a.inc_cat == k])
    end

    A = zeros(n,q) # n x q matrix
    for id in filter!(id -> balt_abm[id] isa CHANCE_C.House, collect(Agents.schedule(abm)))
        A[abm[id].bg_id, abm[id].quality] = abm[id].available_units
    end

    #Calculate Penalty Matrix
    Z = zeros(n,q,c)
    for j in 1:q
        for k in 1:c
            Z[:,j,k] = repeat([abs(j-k) * 50000], n)
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
    
    #return objective_value(model)
    #return value.(P)

end

#Benchmark function
b = @benchmarkable AgentMigration(balt_abm) setup=(balt_abm = Simulator(default_df, balt_base, balt_levee, model_evolve; slr_scen = slr_scen, slr_rate = slr_rate, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)) seconds=10 evals=1

run(b)
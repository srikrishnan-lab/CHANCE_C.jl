
### For timing of model executions and specific evolution functions
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
using DataStructures
using Statistics,StatsBase,Distributions
using Agents

using BenchmarkTools, TimerOutputs

### Load input Data
f_df = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data", "synth_flood_phil.csv")))

##For BG
#open bg file
phil_bg = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/philly_bg_2019.csv")))
#groupby BG
grouped_phil_bg = groupby(phil_bg, :GEOID)

##load pop data
phil_cbsa_base_pop = DataFrame(CSV.File(joinpath(dirname(dirname(@__DIR__)), "philadelphia-data/census_data/synth_pop/pop_files/philly_cbsa_pop_0.csv")))
#drop missing values
dropmissing!(phil_cbsa_base_pop, :NP)
#drop rows with negative income
subset!(phil_cbsa_base_pop, :adj_income_2019 .=> ByRow(!<(0)))

#Subset to Phil. County (Not part of function)
#phil_base_pop = subset(phil_cbsa_base_pop, :county => x -> x .== 42101)


#Define relevant parameters
no_of_years = 38
start_year = 1981
no_hhs_per_agent=10
grouped = true
group_col = "adj_income_2019"
cutoff_dict = OrderedDict("low"=> [-60000.00,25000.00], "medium"=>[25000.00,75000.00], "high"=>[75000.00, 1e7])
bg_cat = Dict(:col =>"income_cat", :group => ["low", "medium", "high"])
house_budget_mode = "perc"
house_choice_mode = "flood_mem_utility"
risk_averse = 0.3
flood_mem = 10
growth_rate = 0.01
seed = 1500

tmr = TimerOutput()

#Define agent steps
function ag_step!(agent::CHANCE_C.HHAgent, model::ABM)
    #Do nothing  
end
 
function ag_step!(agent::CHANCE_C.BlockGroup, model::ABM)
    CHANCE_C.flooded!(agent, model; model.flood_hazard...)
    CHANCE_C.agent_prob!(agent, model; model.relo_sampler...)
end
 
function ag_step!(agent::CHANCE_C.Queue, model::ABM)
    CHANCE_C.AgentLocation(agent, model; model.agent_relocate...)
end
 
function bl_step!(agent::CHANCE_C.BlockGroup, model::ABM)
    CHANCE_C.BuildingDevelopment(agent, model; model.build_develop...)
    CHANCE_C.HousingPricing(agent, model; model.house_price...)
end

#Define model evolution
function evo_step!(model::ABM)
    #Update Year
    model.tick += 1
    #clear utilities df
    empty!(model.hh_utilities_df)
    #create new agents
    @timeit tmr "Add Migrating Agents" CHANCE_C.AgentMigration(model; model.agent_creation...) 
    #Determine relocating HHAgents and potential moving locations
    @timeit tmr "BG Agent Step" begin
        for id in filter!(id -> model[id] isa CHANCE_C.BlockGroup, collect(Agents.schedule(model)))
            ag_step!(model[id],model)
        end
    end
    @timeit tmr "Queue Agent Step" begin
        for id in filter!(id -> model[id] isa CHANCE_C.Queue, collect(Agents.schedule(model)))
            ag_step!(model[id],model)
        end
    end

    #run Housing Market to move HHAgents to desired locations
    @timeit tmr "Housing Market" CHANCE_C.HousingMarket(model) 
 
    #Update BlockGroup conditions
    @timeit tmr "BG block Step" begin
    
        for id in filter!(id -> model[id] isa CHANCE_C.BlockGroup, collect(Agents.schedule(model)))
            bl_step!(model[id], model)
            try
                model[id].avg_hh_income = mean([a.income for a in agents_in_position(model[id].pos, model) if a isa HHAgent])
            catch  #if not incomes_bg:  # i.e. no households reside in block group
                model[id].avg_hh_income = NaN
            end
            
        end
    end
    @timeit tmr "Landscape Statistics" begin
        CHANCE_C.LandscapeStatistics(model)
        model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])
    end
    
end

### Simple measure of model performance ###

## Calculate Flood matrix and Dict for ABM input
f_dict, f_matrix = CHANCE_C.flood_history(f_df; no_of_years = no_of_years, start_year = start_year)

### Initialize ABM
phil_abm = CHANCE_C.Simulator(phil_bg, phil_cbsa_base_pop, f_dict, f_matrix, evo_step!; no_of_years = no_of_years, no_hhs_per_agent = no_hhs_per_agent,
house_budget_mode = house_budget_mode, house_choice_mode = house_choice_mode, grouped = grouped, group_col = group_col, cutoff_dict = cutoff_dict, bg_cat = bg_cat,
pop_growth_perc = growth_rate, risk_averse = risk_averse, flood_mem = flood_mem, seed = seed)

step!(phil_abm)
show(tmr)
reset_timer!(tmr)

##Performance Measure 
b = @benchmarkable step!(phil_abm, no_of_years) setup=(phil_abm = CHANCE_C.Simulator(phil_bg, phil_cbsa_base_pop, f_dict, f_matrix, evo_step!; no_of_years = no_of_years, no_hhs_per_agent = no_hhs_per_agent,
house_budget_mode = house_budget_mode, house_choice_mode = house_choice_mode, grouped = grouped, group_col = group_col, cutoff_dict = cutoff_dict, bg_cat = bg_cat,
risk_averse = risk_averse, flood_mem = flood_mem, seed = seed)) seconds=1800 evals=1 samples = 10

v1_1_time = run(b)
BenchmarkTools.save(joinpath(@__DIR__, "benchmarks/time_v1-1.json"), v1_1_time)

#reset_timer!(tmr)



#Collect baseline run 
include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))
adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]

balt_abm=Simulator(default_df, balt_base, balt_levee; slr_scen = slr_scen, slr_rate = slr_rate, scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

#Time data collection
#reset_timer!(tmr)


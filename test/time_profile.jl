
### For timing of model executions and specific evolution functions
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
using Agents

using BenchmarkTools, TimerOutputs

## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_levee.csv")))


#Define relevant parameters
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 50
perc_growth = 0.02
perc_move = 0.025
house_choice_mode = "flood_mem_utility"
flood_coef = -10.0^5
levee = false
breach = true
slr_scen = "medium" #Select SLR Scenario to use (choice of "low", "medium", and "high")
slr_rate = [3.03e-3,7.878e-3,2.3e-2] #Define SLR Rate of change for each scenario ( list order is "low", "medium", and "high")
breach_null = 0.4 
risk_averse = 0.3 
flood_mem = 10 
fixed_effect = 0

tmr = TimerOutput()
#Define model evolution
function evo_step!(model::ABM)
    #Update Year
    model.tick += 1
    #clear utilities df
    empty!(model.hh_utilities_df)
    #create new agents
    @timeit tmr "New Agent Creation" CHANCE_C.NewAgentCreation(model; model.agent_creation...) 
    #Determine relocating HHAgents and potential moving locations
    @timeit tmr "Agent Step" begin
        for id in Agents.schedule(model)
            CHANCE_C.agent_step!(model[id],model)
        end
    end
    #run Housing Market to move HHAgents to desired locations
    @timeit tmr "Housing Market" CHANCE_C.HousingMarket(model) 
 
    #Update BlockGroup conditions
    #@timeit tmr "BG step" begin
    """
    for id in filter!(id -> model[id] isa BlockGroup, collect(Agents.schedule(model)))
        block_step!(model[id], model)
        try
            model[id].avg_hh_income = mean([a.income for a in agents_in_position(model[id].pos, model) if a isa HHAgent])
        catch  #if not incomes_bg:  # i.e. no households reside in block group
            model[id].avg_hh_income = NaN
        end
         
    end
    #end
    """
    @timeit tmr "Landscape Statistics" begin
        CHANCE_C.LandscapeStatistics(model)
        model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])
    end
end
### Simple measure of model performance ###
balt_abm=Simulator(default_df, balt_base, balt_levee; slr_scen = slr_scen, slr_rate = slr_rate, scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

step!(balt_abm, dummystep, evo_step!, no_of_years)
show(tmr)
reset_timer!(tmr)

##Performance Measure 
b = @benchmarkable step!(balt_abm, $dummystep, $evo_step!, $no_of_years) setup=(balt_abm=Simulator(default_df, balt_base, balt_levee; slr_scen = slr_scen, slr_rate = slr_rate, scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)) seconds=600 evals=1

run(b)





#Collect baseline run 
include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))
adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]

balt_abm=Simulator(default_df, balt_base, balt_levee; slr_scen = slr_scen, slr_rate = slr_rate, scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse,
 flood_mem = flood_mem, fixed_effect = fixed_effect)

#Time data collection
#reset_timer!(tmr)
adf, _ = run!(balt_abm, dummystep, evo_step!, 50; adata)
#show(tmr)

#Save df
CSV.write(joinpath(@__DIR__,"dataframes/adf_balt_nobuild.csv"), adf)

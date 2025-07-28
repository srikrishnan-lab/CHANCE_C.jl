
### For timing of model executions and specific evolution functions
import Pkg
Pkg.activate(".")
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
using DataStructures
using Statistics,StatsBase,Distributions
using Agents

using BenchmarkTools, TimerOutputs

## Import data
data_location = "philadelphia-data/model_inputs"
bg_file = "phil_flood_bg_2019_nomiss_v1.csv"
pop_file = "philly_cbsa_pop_0.csv"
flood_file = "phil_flood_hist_year.csv"

##Read in Demographic Data
phil_bg = DataFrame(CSV.File(joinpath(dirname(pwd()), data_location, bg_file)))
phil_cbsa_base_pop = DataFrame(CSV.File(joinpath(dirname(pwd()), data_location, "pop_files", pop_file)))

#drop missing values
dropmissing!(phil_cbsa_base_pop, :NP)
#For rows with people and negative income, set income to bottom 10%
inc_bot_10 = quantile(subset(phil_cbsa_base_pop, [:NP .=> ByRow(>(0)), :adj_income_2019 .=> ByRow(>(0))]).adj_income_2019, [0.10])[1]
@. phil_cbsa_base_pop.adj_income_2019 = ifelse.(phil_cbsa_base_pop.NP > 0 && phil_cbsa_base_pop.adj_income_2019 <= 0, inc_bot_10, phil_cbsa_base_pop.adj_income_2019)

##Read in flood data
phil_flood = DataFrame(CSV.File(joinpath(dirname(pwd()), data_location, flood_file)))
#transform df to correct format
phil_flood_record = unstack(phil_flood, :GEOID, :year, :perc_flood_extent)
#Extra edits
phil_flood_record[!,"1982"] = zeros(size(phil_flood_record)[1])
select!(phil_flood_record, "GEOID", "1981", "1982", Not(["1982", "2019"]), "2019")

synth_flood_record = DataFrame(CSV.File(joinpath(dirname(pwd()), "CHANCE_C.jl","data","synth_flood_phil.csv")))
select!(synth_flood_record, "GEOID", "1981", "1982", Not(["1980", "1982", "2019"]), "2019")
synth_notin_phil = copy(phil_flood_record[phil_flood_record.GEOID .∉ Ref(synth_flood_record.GEOID),:])
synth_notin_phil[!, 2:end] .= 0
append!(synth_flood_record, synth_notin_phil)

synth_flood_record = synth_flood_record[synth_flood_record.GEOID .∈ Ref(phil_flood_record.GEOID),:]
#Define relevant parameters
f_df = synth_flood_record

no_of_years = 39
start_year = 1981
no_hhs_per_agent=10
growth_rate = 0.01
grouped = true
group_col = "adj_income_2019"
cutoff_dict = OrderedDict(1 => [-60000.00,25000.00], 2 =>[25000.00,75000.00], 3 =>[75000.00, 1e7]) #1=> "low income", 2=> "medium income", 3=> "high income"
bg_cat = Dict(:col =>"income_cat", :group => [1,2,3])
util_coef = Dict(1=> [0.5, 0.5], 2=> [0.5, 0.5], 3=> [0.5, 0.5])
house_budget_mode = "rhea"
rhea_coef = 0.70
house_choice_mode = "flood_ind_utility"
penalty = 0.5
flood_coefficient = 0.5
build_inc_perc = 0.1
price_inc_perc = 0.1
risk_averse = 0.5
base_move = 0.01
flood_mem = 10
levee = false
f_e = 0.0
standardization = "normal"
stay_prob = 1.0
seed = 1500

tmr = TimerOutput()

#Define agent steps
function ag_step!(agent::CHANCE_C.HHAgent, model::ABM)
    CHANCE_C.agent_prob!(agent, model; model.relo_sampler...)
end
 
function ag_step!(agent::CHANCE_C.BlockGroup, model::ABM)
    CHANCE_C.flooded!(agent, model; model.flood_hazard...)    
end
 
function ag_step!(agent::CHANCE_C.Queue, model::ABM)
    CHANCE_C.AgentLocation(agent, model; model.agent_relocate...)
end
 
function bl_step!(agent::CHANCE_C.BlockGroup, model::ABM)
    CHANCE_C.HousingPricing(agent, model; model.house_price...)
    CHANCE_C.BuildingDevelopment(agent, model; model.build_develop...)
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
    #Determine relocating HHAgents and potential moving locations
    @timeit tmr "HH Agent Step" begin
        for id in filter!(id -> model[id] isa CHANCE_C.HHAgent && model[id].bg_id > 0, collect(Agents.schedule(model)))
            ag_step!(model[id],model)
        end
    end
    @timeit tmr "Queue Agent Step" begin
        for id in filter!(id -> model[id] isa CHANCE_C.Queue, collect(Agents.schedule(model)))
            ag_step!(model[id],model)
        end
    end

    #run Housing Market to move HHAgents to desired locations
    @timeit tmr "Housing Market" CHANCE_C.HousingMarket(model; model.hh_market...) 
 
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
        CHANCE_C.LandscapeStatistics(model;grouped = model.build_develop[:grouped])
        model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])
    end
    
end

function evo_alt_step!(model::ABM)
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
    #Determine relocating HHAgents and potential moving locations
    @timeit tmr "HH Agent Step" begin
        for id in filter!(id -> model[id] isa CHANCE_C.HHAgent && model[id].bg_id > 0, collect(Agents.schedule(model)))
            ag_step!(model[id],model)
        end
    end
    @timeit tmr "Landscape Statistics" begin
        CHANCE_C.LocationUpdate(model;grouped = model.build_develop[:grouped])
    end
    #run Housing Market to move HHAgents to desired locations
    @timeit tmr "Housing Market" CHANCE_C.HouseMarket(model; model.hh_market...) 
 
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
    @timeit tmr "Landscape Statistics #2" begin
        CHANCE_C.LocationUpdate(model;grouped = model.build_develop[:grouped])
        model.total_population = sum([a.population for a in allagents(model) if a isa BlockGroup])
    end
    
end


### Simple measure of model performance ###
mod_evo = evo_alt_step!
### Initialize ABM
time_abm = CHANCE_C.Simulator(phil_bg, phil_cbsa_base_pop, f_df, mod_evo; start_year = start_year, no_of_years = no_of_years, no_hhs_per_agent = no_hhs_per_agent,
standardization = standardization, house_budget_mode = house_budget_mode, rhea_coef = rhea_coef, house_choice_mode = house_choice_mode, grouped = grouped, group_col = group_col, cutoff_dict = cutoff_dict, bg_cat = bg_cat,
simple_anova_coefficients = util_coef, flood_coefficient = flood_coefficient, penalty = penalty, pop_growth_perc = growth_rate, stock_increase_perc = build_inc_perc, price_increase_perc = price_inc_perc,
risk_averse = risk_averse, flood_mem = flood_mem, perc_move = base_move, levee=levee, fixed_effect = f_e, stay_prob = stay_prob, seed = seed)

step!(time_abm, no_of_years)
show(tmr)
reset_timer!(tmr)

##Performance Measure 
b = @benchmarkable step!(time_abm, no_of_years) setup=(time_abm = CHANCE_C.Simulator(phil_bg, phil_cbsa_base_pop, f_df, mod_evo; start_year = start_year, no_of_years = no_of_years, no_hhs_per_agent = no_hhs_per_agent,
standardization = standardization, house_budget_mode = house_budget_mode, rhea_coef = rhea_coef, house_choice_mode = house_choice_mode, grouped = grouped, group_col = group_col, cutoff_dict = cutoff_dict, bg_cat = bg_cat,
simple_anova_coefficients = util_coef, flood_coefficient = flood_coefficient, penalty = penalty, pop_growth_perc = growth_rate, stock_increase_perc = build_inc_perc, price_increase_perc = price_inc_perc,
risk_averse = risk_averse, flood_mem = flood_mem, perc_move = base_move, levee=levee, fixed_effect = f_e, stay_prob = stay_prob, seed = seed)) seconds=1800 evals=1 samples = 10

v1_1_time = run(b)
BenchmarkTools.save(joinpath(@__DIR__, "benchmarks/time_v1-1.json"), v1_1_time)

#reset_timer!(tmr)


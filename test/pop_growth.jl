### Check to see if model population is growing over time ###
#Want to make sure that HHagents aren't removed prematurely
#Also want to check affordability of properties across income categories

#Load Project Environment
import Pkg
Pkg.activate(".")
Pkg.instantiate()

#Load Packages
using CSV, DataFrames
using DataStructures
using Agents
using Statistics,StatsBase,Distributions
using CategoricalArrays

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C
#Load file for collecting data
include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))

###Load Input data:
##For flood history input
f_df = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data", "synth_flood_phil.csv")))

##For BG
#open bg file
phil_bg = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/phil_flood_bg_2019_v2.csv")))

##load pop data
phil_cbsa_base_pop = DataFrame(CSV.File(joinpath(dirname(dirname(@__DIR__)), "philadelphia-data/model_inputs/pop_files/philly_cbsa_pop_0.csv")))
#drop missing values
dropmissing!(phil_cbsa_base_pop, :NP)
#For rows with people and negative income, set income to bottom 10%
inc_bot_10 = quantile(subset(phil_cbsa_base_pop, [:NP .=> ByRow(>(0)), :adj_income_2019 .=> ByRow(>(0))]).adj_income_2019, [0.10])[1]
@. phil_cbsa_base_pop.adj_income_2019 = ifelse.(phil_cbsa_base_pop.NP > 0 && phil_cbsa_base_pop.adj_income_2019 <= 0, inc_bot_10, phil_cbsa_base_pop.adj_income_2019)

#Subset to Phil. County (Not part of function)
phil_base_pop = subset(phil_cbsa_base_pop, :county => x -> x .== 42101)

#Define input Parameters
no_of_years = 39
start_year = 1981
no_hhs_per_agent=10
growth_rate = 0.00
grouped = true
group_col = "adj_income_2019"
cutoff_dict = OrderedDict(1 => [-60000.00,25000.00], 2 =>[25000.00,75000.00], 3 =>[75000.00, 1e7]) #1=> "low income", 2=> "medium income", 3=> "high income"
bg_cat = Dict(:col =>"income_cat", :group => [1,2,3])
simple_anova_coefficients = Dict(1=> [0.5, 0.5], 2=> [0.5, 0.5], 3=> [0.5, 0.5])
house_budget_mode = "rhea"
house_choice_mode = "flood_ind_utility"
risk_averse = 0.5
base_move = 0.01
flood_mem = 10
flood_coefficient = 0.5
seed = 1500

# Calculate Flood matrix and Dict for ABM input
f_matrix, f_dict = CHANCE_C.flood_history(f_df; no_of_years = no_of_years, start_year = start_year)
#Initialize model 
phil_abm = CHANCE_C.Simulator(phil_bg, phil_base_pop, f_matrix, f_dict, CHANCE_C.model_step!; no_of_years = no_of_years, no_hhs_per_agent = no_hhs_per_agent,
house_budget_mode = house_budget_mode, house_choice_mode = house_choice_mode, grouped = grouped, group_col = group_col, cutoff_dict = cutoff_dict, bg_cat = bg_cat,
pop_growth_perc = growth_rate, simple_anova_coefficients = simple_anova_coefficients, risk_averse = risk_averse, flood_mem = flood_mem, perc_move = base_move, seed = seed)

#Check initial propulation counts, avg income
sum([hh_low(agent) for agent in allagents(phil_abm) if agent isa HHAgent && agent.bg_id > 0])
sum([hh_med(agent) for agent in allagents(phil_abm) if agent isa HHAgent && agent.bg_id > 0])
sum([hh_high(agent) for agent in allagents(phil_abm) if agent isa HHAgent && agent.bg_id > 0])
#Budget 
low_inc = [agent.house_budget for agent in allagents(phil_abm) if agent isa HHAgent && Bool(hh_low(agent))]
mean(low_inc)
minimum(low_inc)
maximum(low_inc)
med_inc = [agent.house_budget for agent in allagents(phil_abm) if agent isa HHAgent && Bool(hh_med(agent))]
mean(med_inc)
minimum(med_inc)
maximum(med_inc)
high_inc = [agent.house_budget for agent in allagents(phil_abm) if agent isa HHAgent && Bool(hh_high(agent))]
mean(high_inc)
minimum(high_inc)
maximum(high_inc)
#Occupancy Pop
sum([occ_low(agent) for agent in allagents(phil_abm) if agent isa BlockGroup])
sum([occ_med(agent) for agent in allagents(phil_abm) if agent isa BlockGroup])
sum([occ_high(agent) for agent in allagents(phil_abm) if agent isa BlockGroup])
#check initial vacancies
sum([agent.available_units[1] for agent in allagents(phil_abm) if agent isa BlockGroup])
sum([agent.available_units[2] for agent in allagents(phil_abm) if agent isa BlockGroup])
sum([agent.available_units[3] for agent in allagents(phil_abm) if agent isa BlockGroup])
#Check Property prices 
low_prop = filter(:income_cat => f-> f == 1, phil_abm.df)
med_prop = filter(:income_cat => f-> f == 2, phil_abm.df)
high_prop = filter(:income_cat => f-> f == 3, phil_abm.df)

count(ismissing, low_prop.market_value)
mean(skipmissing(low_prop.market_value))
maximum(skipmissing(low_prop.market_value))
minimum(skipmissing(low_prop.market_value))

count(ismissing, med_prop.market_value)
mean(skipmissing(med_prop.market_value))
maximum(skipmissing(med_prop.market_value))
minimum(skipmissing(med_prop.market_value))

count(ismissing, high_prop.market_value)
mean(skipmissing(high_prop.market_value))
maximum(skipmissing(high_prop.market_value))
minimum(skipmissing(high_prop.market_value))

#Evolve the model 10 years
step!(phil_abm, 10)
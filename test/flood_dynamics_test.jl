### ###
include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C
using Distributions
using CSV, DataFrames
using Agents
using StatsBase

include(joinpath(dirname(@__DIR__),"src/core/model_evolution.jl"))

## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-housing-data/model_inputs/surge_area_baltimore_levee.csv")))

scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 20
perc_move = 0.025
house_choice_mode = "flood_mem_utility"
levee = false
breach = true 
breach_null = 0.45 
risk_averse = 0.3 
flood_mem = 10 
f_e = 0

#Initalize and step through abm for 15 years 
fd_abm = CHANCE_C.Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
perc_move = perc_move, house_choice_mode = house_choice_mode, levee = levee, breach = breach, breach_null = breach_null, risk_averse = risk_averse, flood_mem = flood_mem, fixed_effect = f_e)

step!(fd_abm,dummystep,CHANCE_C.model_step!, 1)
## Check Agent Prob function
agent = fd_abm[1]
model = fd_abm
#Fixed effect: define scaling factor depending on levee presence
scale_factor = levee ? 0.1 : 0.1 - f_e
#Calculate flood probability based on risk averse value
if agent.flood_hazard == 0
    flood_prob = perc_move
elseif risk_averse == 0
    #flood_prob = 1/(1+ exp(-20((sum(model[calc_house].flood[time_back])/mem) - 0.1)))
    flood_prob = 1/(1+ exp(-20((agent.flood_hazard/flood_mem) - 0.1)))  + perc_move
elseif risk_averse == 1
    flood_prob = 0
else
    #flood_prob = 1/(1+ exp(-10((sum(model[calc_house].flood[time_back])/mem) - model.risk_averse)))
    flood_prob = 1/(1+ exp(-((agent.flood_hazard/flood_mem) - risk_averse)/scale_factor)) + perc_move
end
 
move_prob = flood_prob <= 1.0 ? flood_prob : 1

bg_agents = [a for a in agents_in_position(agent, model) if a isa HHAgent]
agents_moving = bg_agents[Bool.(rand(model.rng, Binomial(1,move_prob),length(bg_agents)))] #HHAgents moving from BlockGroup
no_of_agents_moving = length(agents_moving)


## Check Utility calculations
#Initalize and step through abm for 15 years 
fd_abm = CHANCE_C.Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
perc_move = perc_move, house_choice_mode = house_choice_mode, levee = levee, breach = breach, breach_null = breach_null, risk_averse = risk_averse, flood_mem = flood_mem, fixed_effect = f_e)


fd_abm.tick += 1

for id in filter!(id -> fd_abm[id] isa BlockGroup, collect(Agents.schedule(fd_abm)))
    agent_step!(fd_abm[id], fd_abm)
end

move_agents = collect(agents_in_position(fd_abm[0], fd_abm))
hh_agent = move_agents[2]
bg_budget = subset(fd_abm.df, :new_price => n -> n .<= hh_agent.house_budget)

#calculate sample weights
weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
bg_options = bg_budget[sample(fd_abm.rng, 1:nrow(bg_budget), weights, 10; replace = true), :] 
#Calculate utility of options for household agents
bg_utilities = calc_utility.(eachrow(bg_options), house_choice_mode, Ref(fd_abm); anova_coef = [-121428, 294707, 130553, 128990, 154887], flood_coef = -500000) #Figure out most efficient way to calculate. Maybe just read in entire dataframe instead of iterating over rows

calc_utility(bg_options[8,:], "simple_flood_utility", fd_abm)
#push to bg_sample dataframe
append!(bg_sample.hh_id,repeat([hh_agent.id],bg_sample_size))
append!(bg_sample.bg_id, bg_options.fid_1)
append!(bg_sample.bg_utility, bg_utilities)
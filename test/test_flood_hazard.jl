include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C
using Distributions
using CSV, DataFrames
using Agents
using StatsBase

include(joinpath(dirname(@__DIR__),"src/agent_functions/flood_memory.jl"))

## Load input Data
balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_base.csv")))
balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_levee.csv")))

scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 20
perc_growth = 0.02
house_choice_mode = "flood_mem_utility"
breach = true 
breach_null = 0.45 
risk_averse = 0.3 
flood_mem = 10 
f_e = 0

#Initalize and step through abm for 15 years 
fd_abm = CHANCE_C.Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse, flood_mem = flood_mem, fixed_effect = f_e)

## test
base_extent = select(balt_base, Not([:Column1, :GISJOIN, :fid_1, :area]))
levee_extent = select(balt_levee, Not([:Column1, :GISJOIN, :fid_1, :area]))

Matrix(base_extent) == fd_abm.flood_matrix[:,:,1]
Matrix(levee_extent) == fd_abm.flood_matrix[:,:,2]

sum(fd_abm.flood_matrix[:,:,1] .>= fd_abm.flood_matrix[:,:,2])



fd_abm = CHANCE_C.Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
perc_move = perc_move, house_choice_mode = house_choice_mode, levee = false, breach = breach, breach_null = breach_null, risk_averse = risk_averse, flood_mem = no_of_years, fixed_effect = f_e)

step!(fd_abm,dummystep,CHANCE_C.model_step!, 20)

fh_base = [a.flood_hazard for a in allagents(fd_abm) if a isa BlockGroup]


#for levee
fd_abm_levee = CHANCE_C.Simulator(default_df, balt_base, balt_levee; scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
perc_move = perc_move, house_choice_mode = house_choice_mode, levee = true, breach = breach, breach_null = breach_null, risk_averse = risk_averse, flood_mem = no_of_years, fixed_effect = f_e)

step!(fd_abm_levee,dummystep,CHANCE_C.model_step!, 20)

fh_levee = [a.flood_hazard for a in allagents(fd_abm_levee) if a isa BlockGroup]


sum(fh_base) > sum(fh_levee)

sum(fh_base .>= fh_levee)

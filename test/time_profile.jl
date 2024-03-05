
### For timing of model executions and specific evolution functions


using BenchmarkTools, TimerOutputs

include("../src/model_initialization.jl")
#Import model step function
include("../src/model_evolution.jl")


#Set input parameters
scenario = "Baseline"
intervention = "Baseline"
start_year = 2018
no_of_years = 80


### Simple measure of model performance ###

##Run once to compile functions (ignore output)
balt_abm = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years)
@time step!(balt_abm,dummystep,model_step!,no_of_years)

##Actual performance measure
balt_abm = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years)
@time step!(balt_abm,dummystep,model_step!,no_of_years)

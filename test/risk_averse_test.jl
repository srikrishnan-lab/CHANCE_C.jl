#activate project environment
using Pkg
Pkg.activate(".")
Pkg.instantiate()

##Set up parallell processors
using Distributed
addprocs(12, exeflags="--project=$(Base.active_project())")

@everywhere include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))

@everywhere begin
    using CSV, DataFrames
    using Statistics
    using Agents
    using .CHANCE_C
    using LinearAlgebra
end

@everywhere include(joinpath(dirname(@__DIR__), "src/data_collect.jl"))

##Input Data
@everywhere begin
    balt_base = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_base.csv")))
    balt_levee = DataFrame(CSV.File(joinpath(dirname(pwd()), "baltimore-data/model_inputs/surge_area_baltimore_levee.csv")))
end

## Create wrapper of Simulator function to avoid specifying input data and hyperparameters every time
@everywhere BaltSim(;slr_scen::String, no_of_years::Int64, perc_growth::Float64, house_choice_mode::String, flood_coef::Float64, levee::Bool,
 breach::Bool, breach_null::Float64, risk_averse::Float64, flood_mem::Int64, fixed_effect::Float64, seed::Int64) = Simulator(default_df, balt_base, balt_levee, CHANCE_C.model_step!; 
 slr_scen = slr_scen, no_of_years = no_of_years, pop_growth_perc = perc_growth, house_choice_mode = house_choice_mode, flood_coefficient = flood_coef, levee = levee, 
 breach = breach, breach_null = breach_null, risk_averse = risk_averse, flood_mem = flood_mem, fixed_effect = fixed_effect, seed = seed)


## specify data collection
adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
mdata = [flood_scenario, flood_record, total_fld_area]

#Define model parameters or parameter ranges for ABM initialization
params = Dict(
    :no_of_years => 50,
    :slr_scen => "medium",
    :perc_growth => 0.01,
    :house_choice_mode => "flood_mem_utility",
    :flood_coef => -10.0^5,
    :risk_averse => [0.3, 0.7],
    :levee => false,
    :breach => false,
    :breach_null => 0.4,
    :flood_mem => 10,
    :fixed_effect => 0.0,  
    :seed => collect(range(1000,1999)), 
)

#Run models and collect data
adf, mdf = paramscan(params, BaltSim; parallel = true, showprogress = true, adata, mdata, n = 50)

CSV.write(joinpath(@__DIR__,"dataframes/adf_balt_RA_v2.csv"), adf)
CSV.write(joinpath(@__DIR__,"dataframes/mdf_balt_RA_v2.csv"), mdf)

rmprocs(workers())
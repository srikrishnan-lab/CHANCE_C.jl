module CHANCE_C

using Agents
using CSV, Tables
using DataFrames
using Statistics,StatsBase,Distributions
using Random

export 
    Simulator,
    agent_step!,
    block_step!,
    model_step!

include("core/model_initialization.jl")
include("core/model_evolution.jl")

data_file_path = joinpath(dirname(@__DIR__),"data", "bg_baltimore.csv")
const global default_df = DataFrame(CSV.File(data_file_path))

end
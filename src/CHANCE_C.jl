module CHANCE_C

using Agents
using CSV, Tables
using DataFrames
using Statistics,StatsBase,Distributions
using Random
using Extremes
using JuMP
import HiGHS

export 
    Simulator,
    BlockGroup,
    HHAgent,
    House,
    default_df,
    default_gev,
    agent_step!,
    relo_update!,
    block_step!,
    model_step!,
    step!,
    dummystep,
    run!,
    ensemblerun!,
    levee_breach,
    m_to_ft,
    breach_occur,
    ExistingAgentResampler,
    #AgentLocation,
    AgentMigration,
    #BuildingDevelopment,
    #HousingPricing,
    LandscapeStatistics

#import Agent Types and Flood Dynamics Functions
include("core/agent_structs.jl")
include("core/flood_dynamics.jl")
include("core/model_initialization.jl")
include("core/model_evolution.jl")

data_file_path = joinpath(dirname(@__DIR__),"data", "bg_baltimore.csv")
const global default_df = DataFrame(CSV.File(data_file_path))

end
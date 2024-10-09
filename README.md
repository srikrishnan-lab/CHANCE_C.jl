# CHANCE-C Julia (v1.1)

A Julia port of the python-based CHANCE-C ABM Framework.

## Purpose

This repository holds the data and functions required to create and run a CHANCE-C ABM in julia using Agents.jl. More information about the CHANCE-C Framework can be found in [Yoon et al., 2023](https://doi.org/10.1016/j.compenvurbsys.2023.101979).  To view the original code from which this port is based on, please refer to the original [CHANCE-C repository](https://github.com/jimyoon/icom_abm). This version builds on the original framework by representing flood occurrence dynamically to simulate agent response to changing flood hazard.

## Data reference

A dataframe of Block Group attributes must first be created in order to calculate agent attributes. For the purposes of this port, we use the Baltimore Block Group dataframe, `bg_baltimore`, found in the original [CHANCE-C repository](https://github.com/jimyoon/icom_abm). The csv file for this dataframe, as well as the code to create it, can be found in a separate [data repository.](https://github.com/parinbhaduri/baltimore-housing-data)

## Repository Structure

* `data/` contains all model input files neceesary to initialize the model. Folder currently holds data specific to Baltimore by default, but new files for a different city may be added as long as they follow a similar data structure. Alternatively, these dataframes may be read as inputs during model initialization (see Model Initialization for more).
* `src/` stores the required julia files necessary to run the model. This includes `agents_struct.jl` which defines the agent types, `model_intitialization.jl` that defines the ABM initialization function, and the folders  `agent_functions/` and `model_functions/` which hold functions to evolve agents and the model over time. `CHANCE_C.jl` holds the module that exports theses relevant functions.
* `test/` contains scripts for example model runs and unit test cases for the model evolution. `abm_baltimore_example.jl` provides example code to initialize and evolve one model instance, as well as visualize model results `figure_recreation.jl`.

## Installation

### Software Requirements

This model requires [Julia 1.7.0](https://julialang.org/) or newer to run. Download Julia [here](https://julialang.org/downloads/).

Additionally, CHANCE-C 1.1 uses v5.14 of Agents.jl to run the model.  **This model version is incompatible with v6.0 or later of Agents.jl.** For general information about Agents.jl and its capabilities, please read the package [docs](https://juliadynamics.github.io/Agents.jl/v5.14/).

### Installing CHANCE_C

To install this version of CHANCE_C, access the Pkg REPL and execute the following command:

```julia-repl
pkg> add https://github.com/srikrishnan-lab/CHANCE_C.jl#dynamic_ff
```

Note: It is best practice to set up a julia project environment prior to installing this package and running the model. For an explanation on the julia project environment and accessing the Pkg Repl in Julia, read the [Package docs](https://pkgdocs.julialang.org/v1/getting-started/).

## Getting Started

The following section provides an overview on the inputs and functions necessary to run the model. A step-by-step example of the code needed to initialize, run, and collect data of one model instance can be found under `test/abm_baltimore_example.jl`. In summary, running an ABM in julia requires defining agent types, initializing the model and defining properties, and running a step function to evolve the model and update agent and model parameters. CHANCE-C utilizes three agent types, BlockGroup, HHAgent, and Queue, which are defined under `src/agent_structs.jl`. For more information for defining and running an ABM using Agents.jl, please read the [tutorial](https://juliadynamics.github.io/Agents.jl/stable/tutorial/).

### Model Initialization

A CHANCE-C model instance is initialized using the `Simulator()` function defined in `src/model_initialization.jl`. Inputs for `Simulator` are all defined with their default arguments, so no inputs have to be declared upon declaration to create a default model instance. Important input arguments for `Simulator` include:

* `df`: a Block Group dataframe input to create the BlockGroup and HHAgent agents. The block group dataframe is also saved as a model property (`model.df`). By default, the `bg_baltimore` dataframe is automatically inputted here. To use block groups in a different location, input a different dataframe for this argument, or change the path location pointer to its csv file under `src/model_initialization.jl`. This new dataframe should follow the same structure as the `bg_baltimore` dataframe file. To view the `bg_baltimore `dataframe, please refer to the `/data` folder.
* `no_of_years=10:` number of years that the model will be evolved for. Used to create the size of the vector for the BlockGroup attribute `demand_exceeds_supply`.
* `house_choice_mode= "flood_mem_utility"`: Defines how agent utilities are calculated, and decides which structural variant to use for model evolution.
* `perc_growth =0.01`: Net Population Growth Rate of HHAgents
* `perc_move =0.025:` Base Probability of Agent Movement at each timestep, excluding flood risk perception
* `flood_coef =-10.0^5`: Weight of flood experience on sgent utility function. Applicable only when house_choice_mode = "flood_mem_utility"
* `levee =false`: Determines which intervention scenario to utilize, levee (true) or no-levee (false).
* `breach =true`: Determines whether breaching is considered as a failure mode in the levee scenario
* `slr_scen ="high"`: Select SLR Scenario to use (choice of "low", "medium", and "high")
* `slr_rate = [3.03e-3,7.878e-3,2.3e-2]` Define annual SLR Rate of change for each scenario (list order is "low", "medium", and "high"). Default values are based on the calculated linear rate of change from the [USACE Baltimore Feasibility Study](https://www.nab.usace.army.mil/Portals/63/docs/Civil%20Works/Balt%20CSRM/NAB%20-%2005b%20-%20BaltCSRM%20-%20Draft%20Report%20-%20Appendix%20B%20-%20HNH.pdf).
* `breach_null =0.45:`Likelihood of levee breaching. Adjusts the underlying breach probability function. (Range [0.3, 0.5])
* `risk_averse =0.3`: Defines HHAgent level of Flood Risk Aversion when calculating movement probability. (Range [0,1])
* `flood_mem =10`: Defines HHAgent flood memory duration (years)
* `fixed_effect =0`: Defines the direct level of influence of levee presence on agent flood risk perception, both in terms of agent movement probability and agent utility (Range [0,0.01)

For more details about the optional keyword arguments, please read the descriptions found in `test/abm_baltimore_example.jl`.

### Defining and executing Model Evolution

Once the model is initialized, step functions must be declared to define how agents and the overall model evolve over time. For CHANCE-C, agent and model evolution is defined under one function, `model_step!`, located under `src/model_evolution.jl`. The order of updating functions for one time step within `model_step!` is as follows:

1. `NewAgentCreation` - HHAgents are created and added to the model. The number of agents added is based on the growth rate parameter `pop_growth_perc`
2. `flooded` - Records the total inundatation area within each BlockGroup, based on flood occurrence in the present time step and past time steps within the flood memory window, as specified by `mem`.
3. `agent_prob` - a proportion of HHagents are selected to move in each BlockGroup, primarily based on the level of experienced flood events in each Block Group
4. `AgentLocation` - Moving HHAgents rank a sample of viable BlockGroup locations based on their expected utility. The preferred BlockGroups and their associated utilities, as well as the HHAgents' incomes, are saved as a DataFrame and stored as a model property (`model.hh_utilities_df`)
5. `HousingMarket` - HHAgents are matched with their preferred BlockGroup.  HHAgents are moved to a new location or exit the model based on availability.
6. `BuildingDevelopment` - Housing supply is increased by 5% in BlockGroups with high demand (demand > supply) based on the outcome of `HousingMarket`
7. `HousingPricing` - Housing prices are increased by 5% for BlockGroups with high demand (demand > supply) or decreased for BlockGroups with a continuous period of low demand (demand < supply for multiple consecutive years).
8. `LandcapeStatistics` - Updates block group attribute columns in `model.df` based on updated BlockGroup Attributes from prior functions.

To evolve the model without collecting data, call `step!(model::ABM, agent_step, model_step, no_of_years::Int)`. Again, for CHANCE-C, all agent and model evolution are handled by `model_step!`, so the correct call for evolving a CHANCE-C model is `step!(model::ABM, dummystep, model_step!, no_of_years::Int)`.

### Data Collection & Visualization

To evolve the model while simultaneously collecting data, use the `run!` function. `run!` uses the same inputs as `step!`, with an additional argument, `adata` and `mdata`, specifying what data to collect from agents and the model, respectively. `adata `is a vector of tuples each with three items: an agent attribute to collect, a function to aggregate the data, and a function to filter or specify which agents to collect from. Alternatively, you can specify a function instead of an agent attribute for more advanced data collection. Examples of such functions, as well as agent filtering functions, can be found under `src/data_collect.jl `. `mdata` has the same structure as `adata` without the filtering function specification. To evolve and collect data from multiple models, use `ensemblerun!`with the same inputs as `run!`, with the exception of inputting a vector of model instances as the first argument instead of one model instance. For more information on data collection, please see the docs on [collecting data](https://juliadynamics.github.io/Agents.jl/stable/tutorial/#.-Collecting-data-1).

The output from `run!` are two dataframes for aggregated agent and model data as specified by `adata` and `mdata`. Columns specify the data being collected, and rows specify the time step from which the data has been collected from. From these dataframes, data can be visualized as static plots using any Julia visualization package, such as [Plots.jl](https://docs.juliaplots.org/stable/).

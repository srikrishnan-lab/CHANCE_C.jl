# CHANCE-C Julia

A Julia port of the python-based CHANCE-C ABM Framework.

## Purpose

This repository holds the data and functions required to create and run a CHANCE-C ABM in julia using Agents.jl. More information about the CHANCE-C Framework can be found in [Yoon et al., 2023](https://doi.org/10.1016/j.compenvurbsys.2023.101979).  To view the original code from which this port is based on, please refer to the original [CHANCE-C repository](https://github.com/jimyoon/icom_abm). For general information about Agents.jl and its capabilities, please read the package [docs](https://juliadynamics.github.io/Agents.jl/stable/).

## Data reference

A dataframe of Block Group attributes must first be created in order to calculate agent attributes. For the purposes of this port, we use the Baltimore Block Group dataframe, `bg_baltimore`, found in the original [CHANCE-C repository](https://github.com/jimyoon/icom_abm). The csv file for this dataframe, as well as the code to create it, can be found in a separate [data repository.](https://github.com/parinbhaduri/baltimore-housing-data)

## Repository Structure

* `data/` contains all raw data inputs. Folder currently empty for this model version.
* `src/` stores the required julia files necessary to run the model. This includes `agents_struct.jl` which defines the agent types, `model_intitialization.jl` that defines the ABM initialization function, and the folders  `agent_functions/` and `model_functions/` which hold functions to evolve agents and the model over time.
* `test/` contains scripts for example model runs and unit test cases for the model evolution. `abm_baltimore_example.jl` provides example code to initialize and evolve one model instance, as well as visualize model results. `figure_recreation.jl` provides code to recreate the sensitivity analysis conducted on structural model parameters from [Yoon et al., 2023](https://doi.org/10.1016/j.compenvurbsys.2023.101979).

## Installation

### Setting up Julia Project

It is best practice to set up a julia project environment prior to running the model. Setting up the environment will also install the packages necessary to run the scripts present in this repository. For an explanation on the julia project environment and accessing the Pkg Repl in Julia, read the [Package docs](https://pkgdocs.julialang.org/v1/getting-started/). In summary, after cloning this repository to your device, access the Pkg REPL from the **parent directory** of your cloned repository folder location and execute the following command:

`activate chance-c-julia`

Julia should activate the existing environment from the `Project.toml` file, rather than creating a new environment. To install all necessary dependencies with the correct versions from the `Manifest.toml` file, run `instantiate` in the Pkg REPL.

## Getting Started

The following section provides an overview on the inputs and functions necessary to run the model. A step-by-step example of the code needed to initialize, run, and collect data of one model instance can be found under `test/abm_baltimore_example.jl`. In summary, running an ABM in julia requires defining agent types, initializing the model and defining properties, and running a step function to evolve the model and update agent and model parameters. CHANCE-C utilizes three agent types, BlockGroup, HHAgent, and Queue, which are defined under `src/agent_structs.jl`. For more information for defining and running an ABM using Agents.jl, please read the [tutorial](https://juliadynamics.github.io/Agents.jl/stable/tutorial/).

### Model Initialization

A CHANCE-C model instance is initialized using the `Simulator()` function defined in `src/model_initialization.jl`. Inputs for `Simulator` are all defined with their default arguments, so no inputs have to be declared upon declaration to create a default model instance. Important input arguments for `Simulator` include:

* `df`: a Block Group dataframe input to create the BlockGroup and HHAgent agents. The block group dataframe is also saved as a model property (`model.df`). By default, the `bg_baltimore` dataframe is automatically inputted here. To use block groups in a different location, input a different dataframe for this argument, or change the path pointer to its csv file under `src/model_initialization.jl`.
* `no_of_years:` number of years that the model will be evolved for. Used to create the size of the vector for the BlockGroup attribute `demand_exceeds_supply`.
* `house_choice_mode`: Defines how agent utilities are calculated. Decides which structural variant to use for model evolution. 

Structural variants of CHANCE-C must be declared upon model initialization. To select a structural variant and declare its associated parameter value, refer to the following table:

| Structural variant | `house_choice_mode`      | parameter argument name   | argument type `Float64` |
| ------------------ | -------------------------- | ------------------------- | ------------------------- |
| Disamenity         | "simple_flood_utility"     | `flood_coefficient`     | Negative Real Number      |
| Avoidance          | "simple_avoidance_utility" | `simple_avoidance_perc` | Decimal                   |
| Protection         | "budget_reduction"         | `budget_reduction_perc` | Decimal                   |

For more details about the optional keyword arguments, please read the descriptions found in `test/abm_baltimore_example.jl`.

### Defining and executing Model Evolution

Once the model is initialized, step functions must be declared to define how agents and the overall model evolve over time. For CHANCE-C, agent and model evolution is defined under one function, `model_step!`, located under `src/model_evolution.jl`. The order of updating functions for one time step within `model_step!` is as follows:

1. `NewAgentCreation` - HHAgents are created and added to the model. The number of agents added is based on the growth rate parameter `pop_growth_perc`
2. `ExistingAgentSampler` - a proportion of HHagents are selected to move from each Block Group
3. `AgentLocation` - Moving HHAgents rank a sample of viable BlockGroup locations based on their expected utility. The preferred BlockGroups and their associated utilities, as well as the HHAgents' incomes, are saved as a DataFrame and stored as a model property (`model.hh_utilities_df`)
4. `HousingMarket` - HHAgents are matched with their preferred BlockGroup.  HHAgents are moved to a new location or exit the model based on availability.
5. `Building Development` - Housing supply is increased in BlockGroups with high demand (demand > supply) based on the outcome of HousingMarket
6. `HousingPricing` - Housing prices are increased for BlockGroups with high demand (demand > supply) or decreased for BlockGroups with a continuous period of low demand (demand < supply for multiple consecutive years).
7. `LandcapeStatistics` - Updates block group attribute columns in `model.df` based on updated BlockGroup Attributes from prior functions.

To evolve the model without collecting data, call `step!(model::ABM, agent_step, model_step, no_of_years::Int)`. Again, for CHANCE-C, all agent and model evolution are handled by `model_step!`, so the correct call for evolving a CHANCE-C model is `step!(model::ABM, dummystep, model_step!, no_of_years::Int)`.

### Data Collection & Visualization

To evolve the model while simultaneously collecting data, use the `run!` function. `run!` uses the same inputs as `step!`, with an additional argument, `adata` and `mdata`, specifying what data to collect from agents and the model, respectively. `adata `is a vector of tuples each with three items: an agent attribute to collect, a function to aggregate the data, and a function to filter or specify which agents to collect from. Alternatively, you can specify a function instead of an agent attribute for more advanced data collection. Examples of such functions, as well as agent filtering functions, can be found under `src/data_collect.jl `. `mdata` has the same structure as `adata` without the filtering function specification. To evolve and collect data from multiple models, use `ensemblerun!`with the same inputs as `run!`, with the exception of inputting a vector of model instances as the first argument instead of one model instance. For more information on data collection, please see the docs on [collecting data](https://juliadynamics.github.io/Agents.jl/stable/tutorial/#.-Collecting-data-1).

The output from `run!` are two dataframes for aggregated agent and model data as specified by `adata` and `mdata`. Columns specify the data being collected, and rows specify the time step from which the data has been collected from. From these dataframes, data can be visualized as static plots using any Julia visualization package, such as [Plots.jl](https://docs.juliaplots.org/stable/).

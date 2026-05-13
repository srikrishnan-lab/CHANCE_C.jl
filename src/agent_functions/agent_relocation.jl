"""
    ExistingAgentResampler(agent::BlockGroup, model::ABM; perc_move=0.10)

Randomly selects a percentage of household agents (`HHAgent`) from a given BlockGroup 
and moves them into the relocation queue.

- Identifies all household agents currently in the BlockGroup
- Samples a fraction ('perc_move') of those agents without replacement
- Updates their 'bg_id' to 0 (indicating relocation)
- Moves them to the model's relocation queue (position 0)
- Updates BlockGroup properties:
    - Decreases 'occupied_units'
    - Increases 'available_units'
    - Reduces total 'population' based on household sizes

If fewer than one agent qualifies to move, the function exits early.

# Arguments
- 'agent::BlockGroup': The BlockGroup from which agents are sampled
- 'model::ABM': The agent-based model containing agents and spatial structure

# Parameters
- 'perc_move::Float64=0.10': Fraction of household agents to relocate

# Returns
- 'Nothing'
"""
function ExistingAgentResampler(agent::BlockGroup, model::ABM; perc_move = 0.10)
    bg_agents = [a for a in agents_in_position(agent, model) if a isa HHAgent]
    no_of_agents_moving = Int(round(perc_move * length(bg_agents))) #number of HHAgents moving from BlockGroup
    if no_of_agents_moving < 1
    #not enough agents
        return
    end
    agents_moving = sample(model.rng, bg_agents, no_of_agents_moving; replace = false) #Randomly sampled agents that will move
    #Update BG id property for moving agents
    setproperty!.(agents_moving, :bg_id, 0)
    #Move agents to relocating Queue
    move_agent!.(agents_moving, Ref(model[0].pos), Ref(model))
    #Update occupied and available_units bg properties
    agent.occupied_units -= no_of_agents_moving
    agent.available_units += no_of_agents_moving
    
    agent.population -= sum(getproperty.(agents_moving,:no_hhs_per_agent) .* getproperty.(agents_moving,:hh_size))
end


"""
    agent_prob!(agent::HHAgent, model::ABM;
                levee=false, risk_averse=0.3,
                base_prob=0.10, f_e=0)

Determines whether a household agent relocates based on
flood experience and risk-aversion behavior.

Relocation probability is computed using a logistic response
function scaled by:
- household flood experience
- risk-aversion threshold
- levee protection effects
- baseline relocation probability

If relocation occurs:
- the household is moved into the relocation queue
- the originating BlockGroup housing stock is updated
- local population counts are reduced accordingly

# Arguments
- `agent::HHAgent`: Household agent being evaluated for relocation
- `model::ABM`: Agent-based model containing simulation state

# Keywords
- `levee=false`: Whether levee protection is active
- `risk_averse=0.3`: Flood-risk tolerance threshold
- `base_prob=0.10`: Baseline probability of relocation
- `f_e=0`: Levee effectiveness scaling factor

# Returns
- Nothing. Mutates household and BlockGroup state in place.
"""
function agent_prob!(agent::HHAgent, model::ABM; levee = false, risk_averse = 0.3, base_prob = 0.10, f_e = 0)
 
    ### Calculate logistic Probability ###
   
    #Fixed effect: define scaling factor depending on levee presence
    scale_factor = levee ? 0.1 - f_e : 0.1
    #Calculate flood probability based on risk averse value
    if agent.flood_experience == 0
        flood_prob = base_prob
    elseif risk_averse == 0
        flood_prob = 1/(1+ exp(-20((agent.flood_experience) - 0.1))) + base_prob
    elseif risk_averse == 1
        flood_prob = 0
    else
        flood_prob = 1/(1+ exp(-((agent.flood_experience) - risk_averse)/scale_factor)) + base_prob
    end
     
    move_prob = flood_prob <= 1.0 ? flood_prob : 1
    
    ### Move triggered agent to Queue ###
    if Bool(rand(abmrng(model), Binomial(1,move_prob)))
        #Get Block Group id of agent's location
        bg_id = first(keys(agent.utility))
        setproperty!(agent, :bg_id, 0)
        #Move agents to relocating Queue
        move_agent!(agent, model[0].pos, model)
        model[bg_id].occupied_units[agent.occ_cat] -= 1
        model[bg_id].available_units[agent.occ_cat] += 1

        model[bg_id].population -= getproperty(agent,:no_hhs_per_agent) * getproperty(agent,:hh_size)
    end
end


"""
    AgentLocation(agent::Queue, model::ABM;
                  levee=false, f_e=0.0,
                  bg_sample_size=10,
                  house_choice_mode="simple_anova_utility",
                  budget_reduction_perc=0.10,
                  penalty=50)

Evaluates potential relocation destinations for household agents
stored in the relocation queue.

For relocating households, the function:
- samples candidate BlockGroups
- evaluates housing affordability and utility
- compares candidate utilities against current locations
- records feasible relocation destinations
- updates relocation outcomes if no suitable housing is found

Candidate locations are weighted by housing availability and filtered
according to the selected housing-choice strategy.

If no acceptable destination exists, households may:
- return to their previous BlockGroup
- remain unassigned
- or be removed from the simulation

# Arguments
- `agent::Queue`: Queue agent containing relocating households
- `model::ABM`: Agent-based model containing housing and population data

# Keywords
- `levee=false`: Whether levee protection affects utility evaluation
- `f_e=0.0`: Levee effectiveness scaling factor
- `bg_sample_size=10`: Number of candidate BlockGroups sampled
- `house_choice_mode="simple_anova_utility"`: Housing selection strategy
- `budget_reduction_perc=0.10`: Budget reduction factor for flood-prone areas
- `penalty=50`: Utility mismatch penalty between household and housing categories

# Returns
- Nothing. Updates relocation utility data and household assignment state.
"""
function AgentLocation(agent::Queue, model::ABM; levee = false, f_e = 0.0, bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, penalty = 50)

    if agent.type == :relocating
        loc_df = copy(model.df)
        # Create a GEOID-to-BlockGroup lookup
        geoid_to_bg = Dict{Int64, Int64}()
        for bg in allagents(model)
            if bg isa BlockGroup
                geoid_to_bg[bg.GEOID] = bg.id
            end
        end

        # Use view or filter instead of multiple list comprehensions
        moving_agents = sort!([a for a in agents_in_position(agent, model) if a isa HHAgent], by=a -> a.income, rev=true)

        current_index = 1
        #Preallocate some vectors to reduce memory allocations
        hh_ids = Vector{Int64}(undef, bg_sample_size * length(moving_agents))
        bg_ids = Vector{Int64}(undef, bg_sample_size * length(moving_agents))
        bg_GEOID = Vector{Int64}(undef, bg_sample_size* length(moving_agents))
        bg_cat = Vector{Int64}(undef, bg_sample_size* length(moving_agents))
        bg_utilities = Vector{Float64}(undef, bg_sample_size * length(moving_agents))

        for hh_agent in moving_agents
            # Consolidate budget selection logic
            bg_budget = if house_choice_mode == "simple_avoidance_utility"
                hh_agent.avoidance ? 
                    subset(loc_df, :perc_fld_area => n -> n .<= 0.10, view = true) :
                    subset(loc_df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true, view = true)
            elseif house_choice_mode == "budget_reduction"
                new_house_budget = hh_agent.house_budget * (1 - budget_reduction_perc)
                hh_budget = ifelse.(loc_df.perc_fld_area .>= 0.10, new_house_budget, hh_agent.house_budget)
                subset(loc_df, :market_value => n -> n .<= hh_budget, skipmissing=true, view = true)
            else
                subset(loc_df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true, view = true)
            end


            # Use a more efficient sampling approach
            util_diff = 0
            try
                # Precompute weights to avoid repeated calculations
                weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
                    
                # Check for available locations more efficiently
                valid_locations = findall(weights .> 0)
                if isempty(valid_locations)
                    throw(ErrorException("No affordable locations with available units"))
                end

                #Sample from affordable locations based on weights
                sample_size = min(length(valid_locations), bg_sample_size)
                sampled_indices = sample(abmrng(model), valid_locations, sample_size, replace=false)
                
                #Grab utilities from sampled locations
                loc_utilities = [model[geoid_to_bg[row.GEOID]].current_utility[row.income_cat] - ((hh_agent.group - row.income_cat) * penalty) for row in eachrow(bg_budget[sampled_indices, [:GEOID, :income_cat]])]
                # Find indices of block groups with better utilities than current agent location
                current_utility = first(values(hh_agent.utility))
                util_diff = (current_utility - maximum(loc_utilities)) #/ current_utility
                opt_locs = findall(>(current_utility), loc_utilities)

                # Check if any moves are possible
                if isempty(opt_locs)
                    throw(ErrorException("No better locations found"))
                end
                best_indices = sampled_indices[opt_locs]
                
                #Append future block group properties to vectors
                ind_length = length(best_indices)

                copyto!(hh_ids, current_index, fill(hh_agent.id, ind_length), 1, ind_length)
                copyto!(bg_ids, current_index, getindex.(Ref(geoid_to_bg), bg_budget[best_indices,:GEOID]), 1, ind_length)
                copyto!(bg_GEOID, current_index, bg_budget[best_indices, :GEOID], 1, ind_length)
                copyto!(bg_cat, current_index, bg_budget[best_indices, :income_cat], 1, ind_length)
                copyto!(bg_utilities, current_index, loc_utilities[opt_locs], 1, ind_length)

                current_index += ind_length
                
            catch
                # Migration logic remains similar
                last_bg = model[first(keys(hh_agent.utility))]
                if last_bg.id == -1
                    remove_agent!(hh_agent, model)
                    continue
                end

                stay_prob = 1.5/(1+ exp(-0.6(util_diff)))
                stay_prob = stay_prob <= 1.0 ? stay_prob : 1.0
                if rand(abmrng(model), Binomial(1, stay_prob)) == 1
                    #Revert HHAgent Properties
                    setproperty!(hh_agent, :bg_id, last_bg.id)
                    move_agent!(hh_agent, last_bg.pos, model)
                    #Update Last BG Properties
                    last_bg.occupied_units[hh_agent.occ_cat] += 1
                    last_bg.available_units[hh_agent.occ_cat] -= 1
                    last_bg.population += getproperty(hh_agent, :no_hhs_per_agent) * getproperty(hh_agent, :hh_size)
                else
                    remove_agent!(hh_agent, model)
                end
            end
        end
        
        ##Create df from vectors, append to model properties df
        #Remove extra undef values by using current index
        bg_sample = DataFrame(hh_id = hh_ids[1:current_index-1], bg_id = bg_ids[1:current_index-1], 
        GEOID = bg_GEOID[1:current_index-1], cat = bg_cat[1:current_index-1], bg_utility = bg_utilities[1:current_index-1])
        
        append!(model.hh_utilities_df, bg_sample)
    else
        return 
    end
end

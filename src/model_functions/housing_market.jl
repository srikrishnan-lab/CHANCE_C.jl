"""
Housing Market could probably be simplified using a group-split-combine scheme instead of iterating over agents
"""

function AgentMigration(abm::ABM; growth_rate = 0.01, hh_size = 2.7, no_hhs_per_agent = 10)
    ##Set up LP
    #Utility Matrix 
    U = abm.hh_utilities
    n = size(U)[1]
    q = size(U)[2]
    c = size(U)[3]

    #New incoming agents
    new_population = abm.total_population * growth_rate
    total_agents = fld(((new_population / hh_size) + fld(no_hhs_per_agent, 2)), no_hhs_per_agent)
    new_agents = fld(total_agents, c) 

    m  = zeros(c) # Vector of length c
    for k in 1:c
        m[k] = sum([a.n_move for a in allagents(abm) if a isa HHAgent && a.inc_cat == k]) + new_agents
    end

    A = zeros(n,q) # n x q matrix
    for id in filter!(id -> abm[id] isa CHANCE_C.House, collect(Agents.schedule(abm)))
        A[abm[id].bg_id, abm[id].quality] = abm[id].available_units
    end

    #Calculate Penalty Matrix
    Z = zeros(n,q,c)
    for j in 1:q
        for k in 1:c
            Z[:,j,k] = repeat([abs(j-k) * 50000], n)
        end
    end

    model = Model(HiGHS.Optimizer)
    set_silent(model)
    @variable(model, P[1:n,1:q,1:c] .>= 0)

    @constraint(model, [k = 1:c], sum(P[:,:,k]) <= m[k])

    @constraint(model, [i = 1:n, j = 1:q], sum(P[i,j,:]) <= A[i,j])

    @objective(model, Max, sum(P .* U .- Z))

    optimize!(model)
    @assert is_solved_and_feasible(model)
    
    #return objective_value(model)
    #return value.(P)
    ReloMat = value.(P) 

    for id in filter!(id -> abm[id] isa HHAgent || abm[id] isa House, collect(Agents.schedule(abm)))
        relo_update!(abm[id], ReloMat)
    end

end


### Test initializing agents with input data and functions
using CSV, DataFrames
using CategoricalArrays
using DataStructures
using Chain
using Statistics
using StatsBase
using Agents

##For BG
#open bg file
phil_bg = DataFrame(CSV.File(joinpath(pwd(), "data/philly_bg_2019.csv")))
#groupby BG
grouped_phil_bg = groupby(phil_bg, :GEOID)


#Try calc_utility function
t_r = grouped_phil_bg[5][grouped_phil_bg[5].income_cat .== "low", :][1,:]
t_r.total_livable_area
calc_utility(t_r, "flood_mem_utility")

for (id, group) in enumerate(grouped_phil_bg)
    create_bg_phil(group, 10; agent_id = id)
end
#try using bg function
create_bg_phil(grouped_phil_bg[5], 10; agent_id = 2)

grouped_phil_bg[4][:, 17:end]





#load pop data
phil_cbsa_base_pop = DataFrame(CSV.File(joinpath(dirname(pwd()), "philadelphia-data/census_data/synth_pop/pop_files/philly_cbsa_pop_0.csv")))
#drop missing values
dropmissing!(phil_cbsa_base_pop, :NP)

#Subset to Phil. County (Not part of function)
phil_base_pop = subset(phil_cbsa_base_pop, :county => x -> x .== 42101)


#Group by Block group (GEOID)
phil_pop_gdf = groupby(phil_base_pop, :GEOID)

#Check vacants by BG 
combine(subset(phil_pop_gdf, :NP => x -> x .== 0.0, ungroup=false), nrow)
#Check households (NP > 0) by BG
combine(subset(phil_pop_gdf, :NP => x -> x .> 0.0, ungroup=false), nrow)

##For this function, Household agents are created within each block group, We'll subset by the given input block group, then group by a continuous category, like income.
test_bg = 421010037022
cutoff_dict = OrderedDict("low"=> [-60000.00,25000.00], "medium"=>[25000.00,75000.00], "high"=>[75000.00, 1e7])
bg_df1 = subset(phil_base_pop, :GEOID => x -> x .== test_bg)
#Look at output from function
t_d, t_df = agent_bin_cont(test_bg, phil_base_pop; no_hhs_per_agent=10, group_col = "adj_income_2019", cutoffs=cutoff_dict, house_budget_mode = "perc", hh_budget_perc = 0.33)


#Calculate number of occupied households within BG
bg_hh_df1 = subset(bg_df1, :NP => x -> x .> 0.0)
#Create group labels by group col
unique(reduce(vcat, collect(values(cutoff_dict))))
cut(bg_hh_df1[:, :adj_income_2019][224:227], unique(reduce(vcat, collect(values(cutoff_dict)))), labels = collect(keys(cutoff_dict)))
bg_hh_df1[:, :adj_income_2019][224:227]
#check function:
for bg_id in unique(phil_base_pop.GEOID)
    println(bg_id)
    dict, ag_df = agent_bin_cont(bg_id, phil_base_pop; no_hhs_per_agent=10, group_col = "adj_income_2019", cutoffs=cutoff_dict, house_budget_mode = "perc", hh_budget_perc = 0.33)
end


"""
#Calculate number of created agents
sub_df1 = rac_gdf[1]
sort!(sub_df1, :HINCP)
sub_df1[:,:group] = map(x->div(x,no_hhs_per_agent), 1:nrow(sub_df1))
hh_bins = combine(groupby(sub_df1, :group), nrow, :RAC1P => maximum => :race, [:NP, :adj_income_2019] .=> mean .=> [:avg_hh_size, :avg_income])
hh_bins[:,2:end]
append!(agent_df, hh_bins[:,2:end])
"""
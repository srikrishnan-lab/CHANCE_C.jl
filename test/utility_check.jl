#Check to see that utility calculations for block groups is sensible across structural choices

disam_abm_null = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
 house_choice_mode = "simple_flood_utility", flood_coefficient = 0)

budg_abm_null = Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
 house_choice_mode = "budget_reduction", budget_reduction_perc = 0)

adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]

adf_null, _ = ensemblerun!([disam_abm_null budg_abm_null], dummystep, model_step!, no_of_years; adata)

flood_pop_change = 100 .* (adf_null.sum_population_f_bgs .- adf_null.sum_pop90_f_bgs) ./ adf_null.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_null.sum_population_nf_bgs .- adf_null.sum_pop90_nf_bgs) ./ adf_null.sum_pop90_nf_bgs


pop_null = Plots.plot(adf_null.step, nf_pop_change, group = adf_null.ensemble,
linecolor = [:blue :green], ls = :solid,
label = ["disamenity" "budget reduction"], lw = 2.5)

Plots.plot!(adf_null.step, flood_pop_change, group = adf_null.ensemble, 
linecolor = [:blue :green], ls = :dash,
 label = false, lw = 2.5)

Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")



##
#Find max structural amenities
max_N_MeanSqfeet = maximum(disam_abm_null.df.N_MeanSqfeet)
max_N_MeanAge = maximum(disam_abm_null.df.N_MeanAge)
max_N_MeanNoOfStories = maximum(disam_abm_null.df.N_MeanNoOfStories)
max_N_MeanFullBathNumber = maximum(disam_abm_null.df.N_MeanFullBathNumber)
max_residuals = maximum(disam_abm_null.df.residuals)
max_perc_fld_area = maximum(disam_abm_null.df.perc_fld_area)

anova_coef = [-121428, 294707, 130553, 128990, 154887]
flood_coef = -5*10^6

best_struct_utility = anova_coef[1] + (anova_coef[2] * max_N_MeanSqfeet) + (anova_coef[3] * max_N_MeanAge) + (anova_coef[4] * max_N_MeanNoOfStories) + 
        (anova_coef[5] * max_N_MeanFullBathNumber) + (1 * max_residuals) 

worst_flood_utility =  (flood_coef * max_perc_fld_area)

flood_utility = (flood_coef * 0.10)

best_struct_utility < abs(worst_flood_utility)
struct_utility < abs(flood_utility)


disamenity_coef = [-2.5 -5*10^6]

disamenity_abms = [Simulator(scenario = scenario, intervention = intervention, start_year = start_year, no_of_years = no_of_years,
house_choice_mode = "simple_flood_utility", flood_coefficient = i) for i in disamenity_coef]
        
adata = [(:population, sum, f_bgs), (:pop90, sum, f_bgs), (:population, sum, nf_bgs), (:pop90, sum, nf_bgs)]
        
adf_dis, _ = ensemblerun!(disamenity_abms, dummystep, model_step!, no_of_years; adata)
        
#Plot results
flood_pop_change = 100 .* (adf_dis.sum_population_f_bgs .- adf_dis.sum_pop90_f_bgs) ./ adf_dis.sum_pop90_f_bgs
nf_pop_change = 100 .* (adf_dis.sum_population_nf_bgs .- adf_dis.sum_pop90_nf_bgs) ./ adf_dis.sum_pop90_nf_bgs
        
disam_col = cgrad(:blues, 7, categorical = true)
pop_disamenity_inter = Plots.plot(adf_dis.step, nf_pop_change, group = adf_dis.ensemble,
linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :solid,
label = disamenity_coef, lw = 2.5)
        
Plots.plot!(adf_dis.step, flood_pop_change, group = adf_dis.ensemble, 
linecolor = [disam_col[1] disam_col[2] disam_col[3] disam_col[4] disam_col[5] disam_col[6] disam_col[7]], ls = :dash,
label = false, lw = 2.5)
        
Plots.xlabel!("Model Year")
Plots.ylabel!("% Change in Population")
        
savefig(pop_disamenity_inter, "test/Figures/disamenity_inter_pop_change.png")
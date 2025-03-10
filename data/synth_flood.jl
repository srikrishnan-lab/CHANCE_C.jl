##Script to create flood dataframe for historical floods in Philadelphia, assuming no flooding has occurred
#Test dataframe with all values being zero

using CSV, DataFrames

#Import dataset
phil_bg = DataFrame(CSV.File(joinpath(pwd(), "data", "philly_bg_2019.csv")))

phil_GEOID = unique(phil_bg, :GEOID)[!,:GEOID]

synth_flood_phil = DataFrame([Symbol(year) => zeros(size(phil_GEOID)) for year in range(1980,2019,step = 1)])
synth_flood_phil[!, :GEOID] = phil_GEOID

CSV.write(joinpath(pwd(), "data", "synth_flood_phil.csv"), synth_flood_phil)
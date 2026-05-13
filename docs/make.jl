using Documenter
using CHANCE_C

makedocs(
    sitename = "CHANCE_C Documentation",
    modules = [CHANCE_C],
    format = Documenter.HTML(),
    checkdocs = :none,
    pages = [
        "Home" => "index.md",
    ]
)
for _, force in pairs(game.forces) do
    force.reset_recipes()
    force.reset_technologies()

    if force.technologies['logistic-train-network'] and force.technologies['logistic-train-network'].researched then
        if force.recipes['logistic-train-stop'] then force.recipes['logistic-train-stop'].enabled = true end
        if force.recipes['ltn-port'] then force.recipes['ltn-port'].enabled = true end
    else
        if force.recipes['logistic-train-stop'] then force.recipes['logistic-train-stop'].enabled = false end
        if force.recipes['ltn-port'] then force.recipes['ltn-port'].enabled = false end
    end
end

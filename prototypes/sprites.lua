for _, color in ipairs { 'blue', 'cyan', 'green', 'orange', 'red', 'yellow' } do
    data:extend {
        {
            type = 'sprite',
            name = 'ltn-sprite-' .. color,
            filename = '__LogisticTrainNetwork__/graphics/sprites/' .. color .. '-button.png',
            size = 64
        }
    }
end

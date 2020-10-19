dataset = "C:\workspace\temp_data\pheromone\1\run1\processed";
load(fullfile(dataset,"data_ID.mat"));
neurons_info = neurons.neurons;
positions = zeros(length(neurons_info), 3);
for i=1:length(neurons_info)
    positions(i, :) = neurons_info(i).position;
end

save(fullfile(dataset,"data_ID.mat"), 'positions', '-append')

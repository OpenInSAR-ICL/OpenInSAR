function [minValue, row, column] = min2d(array2d)
    % Find the minimum value in the 2D array
    [minValue, linearIndex] = min(array2d(:));
    
    % Convert linear index to 2D indices
    [row, column] = ind2sub(size(array2d), linearIndex);
end
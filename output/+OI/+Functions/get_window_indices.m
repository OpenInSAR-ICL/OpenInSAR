function indices = get_window_indices(arraySize, windowSize, centerCoords)
    % getWindowIndices - Returns the indices within a window around specified coordinates.
    %
    % Syntax: indices = getWindowIndices(arraySize, windowSize, centerCoords)
    %
    % Inputs:
    %   arraySize    - A two-element vector [rows, cols] specifying the size of the 2D array.
    %   windowSize   - A two-element vector [windowRows, windowCols] specifying the size of the window.
    %   centerCoords - A two-element vector [row, col] specifying the center coordinates.
    %
    % Outputs:
    %   indices      - A vector of linear indices representing the elements within the window.
    
    % Calculate half the window size on each side
    halfWindow = floor(windowSize ./ 2);
    
    % Define the range for x and y around the center coordinates
    dx = (-halfWindow(2):halfWindow(2)) .* ones(windowSize(1), 1); % x displacement
    dy = (-halfWindow(1):halfWindow(1))' .* ones(1, windowSize(2)); % y displacement
    
    % add the offset
    yGrid = centerCoords(1)+dy(:); 
    xGrid = centerCoords(2)+dx(:);
    
    % Remove out of bounds coordinates
    outOfBounds = (yGrid<1 | yGrid > arraySize(1) | xGrid<1 | xGrid > arraySize(2));
    yGrid(outOfBounds) = [];
    xGrid(outOfBounds) = [];
    
    % Get the indices within the window centered at the specified coordinates
    indices = sub2ind(arraySize, yGrid, xGrid);
end

function displacement3D=los_to_cartesian(d, heading, incidence)
    % Converts heading and incidence angles from degrees to radians
    theta = deg2rad(heading);    % Heading angle in radians
    phi = deg2rad(incidence);    % Incidence angle in radians

    % Calculate the 3D components
    x = d * cos(theta) * sin(phi);
    y = d * sin(theta) * sin(phi);
    z = d * cos(phi);

    % Combine components into a 3D vector
    displacement3D = [x, y, z];

end
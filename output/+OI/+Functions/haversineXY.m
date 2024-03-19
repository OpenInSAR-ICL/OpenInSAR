function [northSouthDist, eastWestDist] = haversineXY(latLonA, latLonB, radius)
% Calculate the approximate distance along the north/south and east/west 
% directions between points given in lat lon coordinates, in meters. 
% Assumes a spherical earth of 6371000 radius. 
% Assumes degrees in and meters out.
% Usage:
%   latLonA = [51.477, 0] % The Greenwich Observatory
%   latLonB = [51.48, -0.008] % The Kings Arms
%   [northDist, eastDist] = haversineXY(latLonA, latLonB)
%   earthRadius = 6371000 %m
%   [northDist, eastDist] = haversineXY(latLonA, latLonB, earthRadius)

szA = size(latLonA);
szB = size(latLonB);
assert(szA(2) == 2 && szB(2) == 2, ...
    'Inputs 1 and 2 should be [Nx2] arrays of lat lon coordinates')
if szA(1)<1
    warning('Empty first argument. No distance computable.')
    [northSouthDist, eastWestDist] = deal([]);
    return
end

% if latLonB is [1x2], expand
if szA(1) ~= szB(1)
    if szB(1) == 1
        latLonB = ones(szA(1), 1) * latLonB;
    else
        error('Argument size mismatch, %i vs %i.',szA(1),szB(1))
    end
end

% default sphere radius
if nargin < 3
    radius = 6371000;
end

hFunc = @(x) sind(x / 2).^2;
hTheta = hFunc(latLonA(:, 1) - latLonB(:, 1)) + ...
    cosd(latLonA(:, 1)) .* cosd(latLonB(:, 1)) .* ...
    hFunc(latLonA(:, 2) - latLonB(:, 2)); 
distance = 2 * radius * atan2(sqrt(hTheta), sqrt(1 - hTheta));

% Calculate azimuth (angle from north) between points
azimuth = atan2d(sind(latLonA(:, 2) - latLonB(:, 2)) .* cosd(latLonB(:, 1)), ...
    cosd(latLonA(:, 1)) .* sind(latLonB(:, 1)) - sind(latLonA(:, 1)) .* cosd(latLonB(:, 1)) .* cosd(latLonA(:, 2) - latLonB(:, 2)));

% Calculate signed north/south and east/west distances
northSouthDist = distance .* cosd(azimuth);
eastWestDist = distance .* sind(azimuth);

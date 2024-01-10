function distance = haversine(latLonA, latLonB, radius)
% Calculate the distance between points given in lat lon coordinates, in
% meters. Assumes a spherical earth of 6371000 radius. Assumes degrees and
% meters.
% Usage:
%   latLonA = [51.477, 0] % The Greenwich Observatory
%   latLonB = [51.48, -0.008] % The Kings Arms
%   dist1 = haversine(latLonA, latLonB)
%   earthRadius = 6371000 %m
%   dist1 = haversine(latLonA, latLonB, earthRadius) % same result as above
% % See https://en.wikipedia.org/wiki/Haversine_formula

assert(size(latLonA, 2) == 2 && size(latLonB, 2) == 2, ...
    'Inputs 1 and 2 should be [Nx2] arrays of lat lon coordinates')
if nargin < 3
    radius = 6371000;
end
hFunc = @(x) sind(x / 2).^2;
hTheta = hFunc(latLonA(:, 1) - latLonB(:, 1)) + ...
    cosd(latLonA(:, 1)) .* cosd(latLonB(:, 1)) .* ...
    hFunc(latLonA(:, 2) - latLonB(:, 2)); 
distance = 2 * radius * atan2(sqrt(hTheta), sqrt(1 - hTheta));

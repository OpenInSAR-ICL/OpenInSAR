function newtheta = phase_triangulation(theCM, maxit)
if nargin<2
    maxit=50;
end

n=size(theCM,1);

[phi, D] = eig(theCM);
bestComponent = 1 + (D(1) > D(end)) .* (n - 1);
newtheta = phi(:, bestComponent);
theCMm1 = theCM .* (1 - eye(n));

%Iterate
for jj=1:maxit
    newtheta=theCMm1*(newtheta);
end
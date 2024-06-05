function unwrappedPhase = unwrap_lsq(x,y,phi,filter_func)

gridt=delaunay(x(:),y(:));
nT=size(gridt,1);
arci1 = [gridt(:,1) gridt(:,2)];
arci2 = [gridt(:,2) gridt(:,3)];
arci3 = [gridt(:,3) gridt(:,1)];
arci = [arci1;arci2;arci3];

% phi should be 2D, time second dim.
if numel(size(phi)) == 3
    phi=reshape(phi,[],size(phi,3));
end
nD = size(phi,2);

arc1 = phi(gridt(:,2),:).*conj(phi(gridt(:,1),:));
arc2 = phi(gridt(:,3),:).*conj(phi(gridt(:,2),:));
arc3 = phi(gridt(:,1),:).*conj(phi(gridt(:,3),:));
arcs = [arc1; arc2; arc3];

[~, referenceIndexInGrid] = max(abs(mean(phi,2)));

sparky = sparse([1:nT*3 1:nT*3 nT*3+1],[arci(:,1)' arci(:,2)' referenceIndexInGrid],[-ones(1,nT*3) ones(1,nT*3) 1]);

if nargin > 3
    filtered_arcs = filter_func(arcs);
    unwrappedPhase = sparky \ [angle(arcs.*conj(filtered_arcs));zeros(1,nD)];
else
    unwrappedPhase = sparky \ [angle(arcs);zeros(1,nD)];
end

function Ahat = nearest_positive_definite(A)

B = (A + A')/2;
[~, Sigma,V] = svd(B);
H = V*Sigma*V';
Ahat = (B+H)/2;
Ahat = (Ahat + Ahat')/2;
p = 1;
k = 0;
while p ~= 0
  [~, p] = chol(Ahat);
  k = k + 1;
  if p ~= 0
    mineig = min(eig(Ahat));
    Ahat = Ahat + (-mineig*k.^2 + eps(mineig))*eye(size(A));
  end
end
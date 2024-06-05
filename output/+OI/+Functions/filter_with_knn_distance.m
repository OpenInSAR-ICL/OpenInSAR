function aps = filter_with_knn_distance(inputPhase, KNN, KNND, sill, decay)
[ngY,ngX,~] = size(KNN);
for iY=ngY:-1:1
    for iX = ngX:-1:1
        dd = KNND(iY,iX,:);
        tt = (1-sill).*exp(-dd(:)./decay);
        tt = tt' ./ sum(tt);
        ssi=(iX-1)*ngY+iY;
        a=tt*inputPhase(KNN(iY,iX,:),:);
        aps(ssi,:) = mean(a, 1);
    end
end
aps=reshape(aps, ngY, ngX, []);
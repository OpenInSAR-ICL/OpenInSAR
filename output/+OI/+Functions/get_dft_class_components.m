function components = get_dft_class_components(vv, vh, channels)

middlePixel = ceil(size(vv,1) / 2);

vv1 = vv(:,1:end-1);
vh1 = vh(:,1:end-1);
vv2 = vv(:,2:end);
vh2 = vh(:,2:end);

vva = log(sum(abs(vv)));
vha = log(sum(abs(vh)));
vvc = abs(sum(vv1.*conj(vv2))./sqrt(sum(abs(vv1).^2).*sum(abs(vv2).^2)));
vhc = abs(sum(vh1.*conj(vh2))./sqrt(sum(abs(vh1).^2).*sum(abs(vh2).^2)));

fva = fft(vva./sqrt(var(vva)));
fvc = fft(vvc./sqrt(var(vvc)));
fha = fft(vha./sqrt(var(vha)));
fhc = fft(vhc./sqrt(var(vhc)));

vvcm = (vv'*vv)./sqrt(sum(abs(vv).^2)'*sum(abs(vv).^2));
vhcm = (vh'*vh)./sqrt(sum(abs(vh).^2)'*sum(abs(vh).^2));

N = size(vv,2);
evcm = eig(abs(vvcm))/N;
evcmc = eig(vvcm)/N;
evhcm = eig(abs(vhcm))/N;
evhcmc = eig(vhcm)/N;

HVV = - sum(evcm.*log(evcm));
HVH = - sum(evhcm.*log(evhcm));
HVVC = - sum(evcmc.*log(evcmc));
HVHC = - sum(evhcmc.*log(evhcmc));
KVV = sum(evcm > 1/N);
KVH = sum(evhcm > 1/N);
NSHP = sum(vv(:,1)~=0);
muVV = mean(vva);
muVH = mean(vha);
varVV = var(vva);
varVH = var(vha);
muV1 = mean(abs(vv(middlePixel,:))).^.5;
muH1 = mean(abs(vh(middlePixel,:))).^.5;
sigV1 = mean(abs(vv(middlePixel,:))).^.5;
sigH1 = mean(abs(vh(middlePixel,:))).^.5;

C1V = abs(mean(vv(middlePixel,:)));
C1H = abs(mean(vv(middlePixel,:)));
muCV = mean(vvc);
muCH = mean(vhc);

components = [real([fva(2:channels) fvc(2:channels) fha(2:channels) fhc(2:channels)]) ...
    imag([fva(2:channels) fvc(2:channels) fha(2:channels) fhc(2:channels)]) ...
    HVV HVH HVVC HVHC KVV KVH ... % 18 17 16 15 14 13
    NSHP muVV muVH varVV varVH ... % 12 11 10 9 8
    muV1 muH1 sigV1 sigH1 ... % 7 6 5 4
    C1V C1H muCV muCH]; % 3 2 1 0

% vvcm = (vv'*vv)./sqrt(sum(abs(vv).^2)'*sum(abs(vv).^2));
% vhcm = (vh'*vv)./sqrt(sum(abs(vv).^2)'*sum(abs(vv).^2));
% consider amp cm, difference, real part of coherence (biased)
function ok = test()

% Test the weight for an unpolarized beam are consistent with an average over
% E-field directions of a polarized beams.

tdmOri = [32 134]*pi/180;
labFrame = [77 11 222]*pi/180;
k = 'y';

w = photoselect(tdmOri,labFrame,k,NaN);

nAlpha = 500;
alpha = linspace(0,pi,nAlpha);
w2 = 0;
for i = 1:numel(alpha)
  w2 = w2 + photoselect(tdmOri,labFrame,k,alpha(i));
end
w2 = w2/nAlpha;

ok = areequal(w,w2,1e-3,'abs');

end
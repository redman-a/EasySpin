function ok = test()

% expansion of isotropic hfc
% system with 1 electron and 3 nuclei

aiso = [100 121 37];

Sys1.Nucs = '1H,1H,1H';
Sys1.A = aiso;

Sys2.Nucs = Sys1.Nucs;
Sys2.A = aiso(:)*[1 1 1];

H1 = ham_hf(Sys1);
H2 = ham_hf(Sys2);

ok = areequal(H1,H2,1e-10,'rel');

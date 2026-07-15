#User need to set <tool_installation> to user's tool path

echo "Sourcing Xcelium license"
setenv XLMHOME /eda/cadence/XCELIUM2409

echo "Sourcing vManager license to lauch IMC tool"
setenv VMGRHOME /eda/cadence/VMANAGER2503

echo "Sourcing Modus License"
setenv MODHOME /eda/cadence/MODUS231

echo "Sourcing Conformal License"
setenv CNFRLHOME /eda/cadence/CONFRML232

echo "Sourcing DDI221 for Genus License"
setenv DDI_GENUS /eda/cadence/DDI231/GENUS231

echo "Sourcing DDI221 for Innovus License"
setenv DDI_INNOVUS /eda/cadence/DDI231/INNOVUS231

echo "Sourcing SSVHOME License"
setenv SSVHOME /eda/cadence/SSV231

echo "Sourcing UVMHOME License"
setenv UVMHOME $XLMHOME/tools.lnx86/methodology/UVM/CDNS-1.1d

 set path = ($XLMHOME/tools.lnx86/bin/64bit \
             $VMGRHOME/bin \
             $MODHOME/tools.lnx86/bin   \
             $CNFRLHOME/tools.lnx86/bin \
	     $DDI_GENUS/tools.lnx86/bin \
	     $DDI_INNOVUS/tools.lnx86/bin \
	     $SSVHOME/tools.lnx86/bin \
             $path )

foreach t ( xrun imc modus genus lec innovus tempus) 
   echo "Found $t at `which $t`"
end

#


#!/bin/bash
DPADir="/opt/solw"
ScriptDir="/opt/solw/automation"
 
action=$1
ReleaseVersionCurrent=$2
ReleaseVersionUpgrade=$3
 
ReleaseVersionCurrentUnderscored=$2
ReleaseVersionCurrentUnderscored=${ReleaseVersionCurrentUnderscored//./_}
 
ReleaseVersionUpgradeUnderscored=$3
ReleaseVersionUpgradeUnderscored=${ReleaseVersionUpgradeUnderscored//./_}
 
if [ "${action}" = "i" ]; then
        ReleaseVersionUpgrade=${ReleaseVersionCurrent}
        ReleaseVersionUpgradeUnderscored=${ReleaseVersionCurrentUnderscored}
fi
 
if [ "${action}" = "x" ]; then
    cd ${DPADir}
    cd dpa_${ReleaseVersionCurrentUnderscored}
        ./shutdown.sh
        sleep 30
        pkill -15 dpa
        sleep 3
        cd ..
        rm -rf dpa_${ReleaseVersionCurrentUnderscored}
 
        echo "!!! Uninstalled including config files !!!"
 
        exit 0
fi
 
cd ${DPADir}
tar -xvf SolarWinds-DPA-${ReleaseVersionUpgrade}-64bit.tar.gz
expect ${ScriptDir}/install.exp $ReleaseVersionUpgradeUnderscored
 
if [ "${action}" = "u" ]; then
        echo "Stopping DPA..."
        cd dpa_${ReleaseVersionCurrentUnderscored}
        ./shutdown.sh
        sleep 30
        pkill -15 dpa
        sleep 3
         cd ..
 
        echo Copying ignite_config folder from "${ReleaseVersionCurrentUnderscored}" to "${ReleaseVersionUpgradeUnderscored}"
        cp -fr dpa_${ReleaseVersionCurrentUnderscored}/iwc/tomcat/ignite_config/*  dpa_${ReleaseVersionUpgradeUnderscored}/iwc/tomcat/ignite_config/
 
        echo Copying conf folder from "${ReleaseVersionCurrentUnderscored}" to "${ReleaseVersionUpgradeUnderscored}"
        cp -fr dpa_${ReleaseVersionCurrentUnderscored}/iwc/tomcat/conf/*  dpa_${ReleaseVersionUpgradeUnderscored}/iwc/tomcat/conf/
 
        echo Moving licensing folder from "${ReleaseVersionCurrentUnderscored}" to "${ReleaseVersionUpgradeUnderscored}"
        mv dpa_${ReleaseVersionCurrentUnderscored}/iwc/tomcat/licensing dpa_${ReleaseVersionUpgradeUnderscored}/iwc/tomcat
fi
 
echo
echo "Removing installer..."
cd ${DPADir}
rm -rf dpa_${ReleaseVersionUpgradeUnderscored}_x64_in
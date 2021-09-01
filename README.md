
# Oracle Cloud Custom Metrics with Oracle Autonomous Database
[Oracle Autonomous Database](https://www.oracle.com/autonomous-database/)(ADB in short) is revolutionizing how data is managed with the introduction of the world’s first "self-driving" database. ADB is powering critical business applications of enterprises, all over the world, as their primary data source. 

ADB provides many important database related [service metrics](https://docs.oracle.com/en-us/iaas/Content/Database/References/databasemetrics_topic-Overview_of_the_Database_Service_Autonomous_Database_Metrics.htm) out of the box, thanks to its deep integration with OCI Monitoring Service. 
But many our innovative customers wish to take their Observability journey a step further:
These **customers want to collect, publish and analyse their own metrics, related their application data stored in the ADB**. In Oracle Monitoring Service terminology we call these [*custom metrics*](https://docs.oracle.com/en-us/iaas/Content/Monitoring/Tasks/publishingcustommetrics.htm). In this tutorial, I will showcase how easily we can achieve it with few lines of PL/SQL scripts! 

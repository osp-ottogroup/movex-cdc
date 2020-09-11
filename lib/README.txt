======================================================
Oracle Free Use Terms and Conditions (FUTC) License 
======================================================
https://www.oracle.com/downloads/licenses/oracle-free-license.html
===================================================================

ojdbc10-full.tar.gz - JDBC Thin Driver and Companion JARS
========================================================
This TAR archive (ojdbc10-full.tar.gz) contains the 19.7 release of the Oracle JDBC Thin driver(ojdbc10.jar), the Universal Connection Pool (ucp.jar) and other companion JARs grouped by category. 

(1) ojdbc10.jar (4,431,447 bytes) - 
(SHA1 Checksum: 3abcfd119f1cc71f16730cdfde8ae18443d5b8c4)
Oracle JDBC Driver compatible with JDK8, JDK9, and JDK11; 
(2) ucp.jar (1,684,253 bytes) - (SHA1 Checksum:299c4305df946e759f204f64809a3560a4a50233)
Universal Connection Pool classes for use with JDK8, JDK9, and JDK11 -- for performance, scalability, high availability, sharded and multitenant databases.
(3) ojdbc.policy (11,515 bytes) - Sample security policy file for Oracle Database JDBC drivers

======================
Security Related JARs
======================
Java applications require some additional jars to use Oracle Wallets. 
You need to use all the three jars while using Oracle Wallets. 

(4) oraclepki.jar (311,000 bytes) - (SHA1 Checksum: e53db9ff1706f349cddd5c0f071734643701e6b6)
Additional jar required to access Oracle Wallets from Java
(5) osdt_cert.jar (210,337 bytes) - (SHA1 Checksum: 3844e4522a306c82ba95f29dbda156462f12f840)
Additional jar required to access Oracle Wallets from Java
(6) osdt_core.jar (312,200 bytes) - (SHA1 Checksum: e19d9bb7d6744bf25501c9af9da74146fc98f984)
Additional jar required to access Oracle Wallets from Java

=============================
JARs for NLS and XDK support 
=============================
(7) orai18n.jar (1,663,954 bytes) - (SHA1 Checksum: 59e13830e5e03bddc03e2cb9f84ea7e48fafe995) 
Classes for NLS support
(8) xdb.jar (265,130 bytes) - (SHA1 Checksum: 5af008e8f1bb1e7bb42ee6081c01fd74b98996b1)
Classes to support standard JDBC 4.x java.sql.SQLXML interface 
(9) xmlparserv2.jar (1,933,746 bytes) - (SHA1 Checksum: 8bf8bae1b10f3d1b770a75994fa9d212124e6a80)
Classes to support standard JDBC 4.x java.sql.SQLXML interface 
====================================================
JARs for Real Application Clusters(RAC), ADG, or DG 
====================================================
(10) ons.jar (156,242 bytes) - (SHA1 Checksum: c59874073eadc7cf8eded6da37b708aaada5096f)
for use by the pure Java client-side Oracle Notification Services (ONS) daemon
(11) simplefan.jar (32,168 bytes) - (SHA1 Checksum: a798b65546f8979a20343e6192fd00e16c532f8b)
Java APIs for subscribing to RAC events via ONS; simplefan policy and javadoc

=================
USAGE GUIDELINES
=================
Refer to the JDBC Developers Guide (https://docs.oracle.com/en/database/oracle/oracle-database/19/jjdbc/index.html) and Universal Connection Pool Developers Guide (https://docs.oracle.com/en/database/oracle/oracle-database/19/jjucp/index.html)for more details. 

======================================================
Oracle Free Use Terms and Conditions (FUTC) License 
======================================================
https://www.oracle.com/downloads/licenses/oracle-free-license.html

===================================================================

ojdbc8-full.tar.gz - JDBC Thin Driver and Companion JARS
========================================================
This TAR archive (ojdbc8-full.tar.gz) contains the 19.6 release of the Oracle JDBC Thin driver(ojdbc8.jar), the Universal Connection Pool (ucp.jar) and other companion JARs grouped by category. 

(1) ojdbc8.jar (4,397,918 bytes) - 
(SHA1 Checksum: f385f5a085bca626491baf0488fc865a43f6b409)
Oracle JDBC Driver compatible with JDK8, JDK9, and JDK11; 
(2) ucp.jar (1,683,003 bytes) - (SHA1 Checksum:8d9c1bf6749ab22483c5017f5a13a4d65fa49c08)
Universal Connection Pool classes for use with JDK8, JDK9, and JDK11 -- for performance, scalability, high availability, sharded and multitenant databases.
(3) ojdbc.policy (11,515 bytes) - Sample security policy file for Oracle Database JDBC drivers

======================
Security Related JARs
======================
Java applications require some additional jars to use Oracle Wallets. 
You need to use all the three jars while using Oracle Wallets. 

(4) oraclepki.jar (311,000 bytes) - (SHA1 Checksum: cc03d8893b3e1419f90d44b25a323d2c49c9c427)
Additional jar required to access Oracle Wallets from Java
(5) osdt_cert.jar (210,337 bytes) - (SHA1 Checksum: 039d8cd0e8f0b0be2f19d560078884e15a4b805f)
Additional jar required to access Oracle Wallets from Java
(6) osdt_core.jar (312,200 bytes) - (SHA1 Checksum: b0be1dbca744143f04ca8cd16e1b078b2b6775d1)
Additional jar required to access Oracle Wallets from Java

=============================
JARs for NLS and XDK support 
=============================
(7) orai18n.jar (1,663,954 bytes) - (SHA1 Checksum: 262f9afc2780fc12b1fde5eb3dfdaf243393277a) 
Classes for NLS support
(8) xdb.jar (265,130 bytes) - (SHA1 Checksum: 1c85f845eb5e74fbb89dd52363b2e6819f1b4760)
Classes to support standard JDBC 4.x java.sql.SQLXML interface 

====================================================
JARs for Real Application Clusters(RAC), ADG, or DG 
====================================================
(9) ons.jar (156,242 bytes) - (SHA1 Checksum: 7542925a23a6841d262bd9b0c2f574e954b41658)
for use by the pure Java client-side Oracle Notification Services (ONS) daemon
(10) simplefan.jar (32,167 bytes) - (SHA1 Checksum: 49e6f05719106f137bb14351646cabcb39120953)
Java APIs for subscribing to RAC events via ONS; simplefan policy and javadoc

=================
USAGE GUIDELINES
=================
Refer to the JDBC Developers Guide (https://docs.oracle.com/en/database/oracle/oracle-database/19/jjdbc/index.html) and Universal Connection Pool Developers Guide (https://docs.oracle.com/en/database/oracle/oracle-database/19/jjucp/index.html)for more details. 

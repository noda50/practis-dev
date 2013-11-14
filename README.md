%%  -*- Mode: Memo -*-

=begin

= memo

== Instruction (shown in github)

=== Create a new repository on the command line

touch README.md
git init
git add README.md
git commit -m "first commit"
git remote add origin git@github.com:noda50/practis-dev.git
git push -u origin master

=== Push an existing repository from the command line

git remote add origin https://github.com/noda50/practis-dev.git
git push -u origin master


# *practis* 
A middleware for exhaustive executions on clouds or clusters.
=====

## Overview
--------
*practis* is a middleware that automates the exhaustive executions for huge number of parameters. These executions are assumed that be executed on cluster environment or a cloud.

User can execute **any** programs on *practis*. Requirements for the execution are so simple. At first, your program shall have an interface to get parameters from *practis*. The second, your program shall have an interface to set results to *practis*. That's all. If you want to know details, please check sample programs.


## Installation
------------
*practis* is a **Ruby** program. Currently, it requires **Ruby** higher than 1.9.X. Some gem packages are used in *practis*, so you need to install required gem packages in Gemfile.

*practis* runs with databases. All of the states, parameters and results are stored in the databases. Followings are the example to install **MySQL** for *practis*.

	# mysql -u root -p
	> CREATE USER $(practis_manager) IDENTIFIED BY ‘password’;
	> CREATE USER $(practis_user) IDENTIFIED BY ‘password’;
	> GRANT ALL ON *.* to ‘$(practis_manager)’@’localhost’ WITH GRANT OPTION;
	> GRANT ALL ON *.* to ‘$(practis_manager)’@’%’ WITH GRANT OPTION;

As you can see from the example, one user named $(practis_manager) is created.


## Quick Start
------------
In this section, one of simple execution example is introduced. In sample directory, some of *practis* examples can be checked.

Ok, let's execute sample/simple_equation! At first, we shall execute **manager**. The **manager** handles *practis* databases including the states of cluster nodes, parameters and results, and also handles messages from **executor**s.

	# ruby bin/manager -D sample/simple_equation
	
That's all!
Of course, you can edit various configurations in configuration files.

Next, let's execute an **executor**. The **executor** is a kind of a client that executes the parameter allocated from **manager**.

	# ruby bin/executor
	
Now, *practis* start running. Please check the states from mysql client.

	# mysql -u $(practis_manager) -p
	> SELECT * FROM simple_equation.parameter;
	> SELECT * FROM simple_equation.result;

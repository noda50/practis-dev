
# scp 


# execute
ruby bin/doe-manager -D sample/crowd_walk.rb -a 150.29.232.52

node=(cassia00a cassia01a cassia02a cassia03a)
for n in $node
do
	ssh ${n} ~/.rbenv/shims/ruby bin/executor -a localhost -m cassia0a -p 30
done
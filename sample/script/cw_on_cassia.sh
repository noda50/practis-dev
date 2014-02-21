node=('cassia00' 'cassia01' 'cassia02' 'cassia03')

# scp 
#for i in ${node[@]}
#do 
#  scp -i ~/.ssh/${i}_rsa -r ~/Programs/temporal_data/sample ${i}a:~/Programs/practis-dev/sample/crowdwalk/
  #ssh -i ~/.ssh/${i}_rsa ${i}a cp -fr ~/Programs/CrowdWalk/netmas/build ~/Programs/practis-dev/sample/crowdwalk/
  #ssh -i ~/.ssh/${i}_rsa ${i}a cp -fr ~/Programs/CrowdWalk/netmas/libs ~/Programs/practis-dev/sample/crowdwalk/
#done

# execution
# executor
for n in ${node[@]}
do
  echo "ssh -i ~/.ssh/${n}_rsa ${n}a -f cd ~/Programs/practis-dev ; ~/.rbenv/shims/ruby bin/executor -a localhost -m cassia0b -p 20 &> ~/log${n}.txt &"
  ssh -i ~/.ssh/${n}_rsa ${n}a -f "cd ~/Programs/practis-dev ; ~/.rbenv/shims/ruby bin/executor -a localhost -m cassia0b -p 20 &> ~/log${n}.txt &"
done
# manager
cd ~/Programs/practis-dev ; nohup ruby bin/doe-manager-web -D sample/crowdwalk -a 150.29.232.52 > ~/log_mngr.txt


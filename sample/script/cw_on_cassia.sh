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
  echo "ssh -i ~/.ssh/${n}_rsa ${n}b -f cd ~/Programs/practis-dev ; ~/.rbenv/shims/ruby bin/executor -a ${n}b -m cassia0b -p 20 &> ~/log${n}.txt &"
  ssh -i ~/.ssh/${n}_rsa ${n}b -f "cd ~/Programs/practis-dev ; ~/.rbenv/shims/ruby bin/executor -a ${n}b -m cassia0b -p 20 &> ~/log${n}.txt &"
done
# manager
cd ~/Programs/practis-dev ; nohup ruby bin/doe-manager-web -D sample/crowdwalk -a cassia0b -w cassia0.sf00.aist.go.jp > ~/log_mngr.txt


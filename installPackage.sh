#----------------
# Update package 
#----------------

if [ ! -f "$1" ]; then
    echo Update package $1 not found, skipping...
    exit
fi

#test archive first
gunzip -c $1 | tar t > /dev/null

if [ $? -ne 0 ]; then
	echo Update package $1 corrupted! Skipping... 
    exit
fi

#update starts from here (no absolute paths in tar)
cd $2

if [ ! -z $3 ]; then
if [ $3 == 'erasePartitionExt3' ]; then
	echo Erasing $2...
	rm -rf $2/*
fi
fi

#apply updated files
tar xf $1

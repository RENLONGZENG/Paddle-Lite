#!/bin/bash
set -e
set -x

## Global variables
workspace=$PWD/$(dirname $0)
readonly workspace=${workspace%%lite/tools*}
WITH_LOG=OFF
WITH_CV=ON
WITH_EXCEPTION=ON


## step 1: compile opt tool
cd $workspace
if [ ! -f build.opt/lite/api/opt ]; then
./lite/tools/build.sh build_optimize_tool
fi
cd build.opt/lite/api
rm -rf models &&  cp -rf $1 ./models

###  models names
models_names=$(ls models)
## step 2. convert models
rm -rf models_opt && mkdir models_opt
for name in $models_names
do
  if [[ $(ls models/$name | wc -l) -gt 2 ]]
  then
    if [[ -f models/$name/__model__ ]]
	then
      ./opt --model_dir=./models/$name --valid_targets=arm --optimize_out=./models_opt/$name --record_tailoring_info=true
    else
      echo "Error: unsupported model format /models/$name"
      exit 1
    fi
  else
    if [[ -f models/$name/model ]] && [[ -f models/$name/params ]]
	then
	./opt --model_file=./models/$name/model --param_file=./models/$name/params --valid_targets=arm --optimize_out=./models_opt/$name --record_tailoring_info=true
	else
	  echo "Error: unsupported model format /models/$name"
	  exit 1
	fi
  fi
done


# step 3. record model infos
rm -rf model_info && mkdir model_info
rm -rf optimized_model && mkdir optimized_model
content=$(ls ./models_opt | grep -v .nb)

for dir_name in $content
do
cat ./models_opt/$dir_name/.tailored_kernels_list >> ./model_info/tailored_kernels_list 
cat ./models_opt/$dir_name/.tailored_kernels_source_list >> ./model_info/tailored_kernels_source_list
cat ./models_opt/$dir_name/.tailored_ops_list >> ./model_info/tailored_ops_list
cat ./models_opt/$dir_name/.tailored_ops_source_list >> ./model_info/tailored_ops_source_list
cp -f ./models_opt/$dir_name.nb optimized_model
done

sort -n ./model_info/tailored_kernels_list | uniq > ./model_info/.tailored_kernels_list
sort -n ./model_info/tailored_kernels_source_list | uniq > ./model_info/.tailored_kernels_source_list
sort -n ./model_info/tailored_ops_list | uniq > ./model_info/.tailored_ops_list
sort -n ./model_info/tailored_ops_source_list | uniq > ./model_info/.tailored_ops_source_list

rm -rf $(ls ./models_opt | grep -v .nb)

# step 4. compiling iOS lib
cd $workspace
./lite/tools/build_ios.sh --with_strip=ON --opt_model_dir=$workspace/build.opt/lite/api/model_info --with_log=OFF --with_cv=ON --with_exception=ON
./lite/tools/build_ios.sh --with_strip=ON --opt_model_dir=$workspace/build.opt/lite/api/model_info --with_log=OFF --arch=armv7 --with_cv=ON  --with_exception=ON

# step 5. pack compiling results and optimized models
result_name=iOS_lib
rm -rf $result_name && mkdir $result_name
cp -rf build.ios.ios.armv7/inference_lite_lib.ios.armv7/ $result_name/armv7
cp -rf build.ios.ios64.armv8/inference_lite_lib.ios64.armv8 $result_name/armv8
cp build.opt/lite/api/opt $result_name/
mv build.opt/lite/api/optimized_model $result_name

# step6. compress the result into tar file
tar zcf $result_name.tar.gz $result_name

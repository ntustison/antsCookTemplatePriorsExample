#!/bin/bash

# user to change
export ANTSPATH=/Users/ntustison/Pkg/ANTs/bin/bin/

DATA_DIR=${PWD}
MALF_DIR=${DATA_DIR}/DataForTemplateLabeling/
ANTS_CT_DIR=${DATA_DIR}/DataForAntsCorticalThickness/
OUT_DIR=${DATA_DIR}/Output/

INPUT_TEMPLATE=${DATA_DIR}/T_template0_slice122.nii.gz

# Do antsCorticalThickness on template.  This is used to get the csf prior.

bash ${ANTSPATH}antsCorticalThickness.sh -d 2 \
  -a $INPUT_TEMPLATE \
  -e ${ANTS_CT_DIR}template_slice80.nii.gz \
  -m ${ANTS_CT_DIR}template_cerebrum_mask_slice80.nii.gz \
  -p ${ANTS_CT_DIR}prior%d_slice80.nii.gz \
  -o ${OUT_DIR}antsCT \
  -u 1

templateBrainMask=${OUT_DIR}antsCTBrainExtractionMask.nii.gz
templateBrain=${OUT_DIR}antsCTBrainExtractionBrain.nii.gz

${ANTSPATH}/ImageMath 2 $templateBrain m $templateBrainMask $INPUT_TEMPLATE

# Do malf labeling on extracted template brain.  This is used to get the rest of the priors
# including part of the csf prior.

command="${ANTSPATH}/antsJointLabelFusion.sh -d 2 -k 0 -o ${OUT_DIR}/ants"
command="$command -t $templateBrain"
for i in `ls ${MALF_DIR}/*Labels*`;
  do
    brain=${i/Labels/BrainCerebellum}
    command="${command} -g $brain -l $i";
  done
$command

# convert labels to 6 tissue (4 in 2-D)
#  1. csf
#  2. gm
#  3. wm
#  4. subcortical gm
#  5. brain stem
#  6. cerebellum

csfLabels=( 4 46 49 50 51 52 )
wmLabels=( 44 45 )
corticalLabels=( 31 32 42 43 47 48 )  # also anything >= 100
subcorticalLabels=( 23 30 36 37 55 56 57 58 59 60 61 62 63 64 75 76 )
brainstemLabels=( 35 )
cerebellumLabels=( 11 38 39 40 41 71 72 73 )

tmp=${OUT_DIR}/tmpForRelabeling.nii.gz
malf=${OUT_DIR}/antsLabels.nii.gz
malf6=${OUT_DIR}/ants6Labels.nii.gz

ThresholdImage 2 $malf $malf6 100 207 2 0

echo "csf: "
for(( j=0; j<${#csfLabels[@]}; j++ ));
  do
    echo ${csfLabels[$j]}
    ${ANTSPATH}/ThresholdImage 2 $malf $tmp ${csfLabels[$j]} ${csfLabels[$j]} 1 0
    ${ANTSPATH}/ImageMath 2 $malf6 + $tmp $malf6
  done

echo "cortex: "
for(( j=0; j<${#corticalLabels[@]}; j++ ));
  do
    echo ${corticalLabels[$j]}
    ${ANTSPATH}/ThresholdImage 2 $malf $tmp ${corticalLabels[$j]} ${corticalLabels[$j]} 2 0
    ${ANTSPATH}/ImageMath 2 $malf6 + $tmp $malf6
  done

echo "white matter: "
for(( j=0; j<${#wmLabels[@]}; j++ ));
  do
    echo ${wmLabels[$j]}
    ${ANTSPATH}/ThresholdImage 2 $malf $tmp ${wmLabels[$j]} ${wmLabels[$j]} 3 0
    ${ANTSPATH}/ImageMath 2 $malf6 + $tmp $malf6
  done

echo "sub-cortex: "
for(( j=0; j<${#subcorticalLabels[@]}; j++ ));
  do
    echo ${subcorticalLabels[$j]}
    ${ANTSPATH}/ThresholdImage 2 $malf $tmp ${subcorticalLabels[$j]} ${subcorticalLabels[$j]} 4 0
    ${ANTSPATH}/ImageMath 2 $malf6 + $tmp $malf6
  done

echo "brain stem: "
for(( j=0; j<${#brainstemLabels[@]}; j++ ));
  do
    echo ${brainstemLabels[$j]}
    ${ANTSPATH}/ThresholdImage 2 $malf $tmp ${brainstemLabels[$j]} ${brainstemLabels[$j]} 5 0
    ${ANTSPATH}/ImageMath 2 $malf6 + $tmp $malf6
  done

echo "cerebellum: "
for(( j=0; j<${#cerebellumLabels[@]}; j++ ));
  do
    echo ${cerebellumLabels[$j]}
    ${ANTSPATH}/ThresholdImage 2 $malf $tmp ${cerebellumLabels[$j]} ${cerebellumLabels[$j]} 6 0
    ${ANTSPATH}/ImageMath 2 $malf6 + $tmp $malf6
  done

# now convert each to a probability map

antsCtCsfPrior=${OUT_DIR}/antsCTPrior1.nii.gz
${ANTSPATH}/SmoothImage 2 ${OUT_DIR}/antsCTBrainSegmentationPosteriors1.nii.gz 1 $antsCtCsfPrior

for(( j=1; j<=6; j++ ));
  do
    prior=${OUT_DIR}/prior${j}.nii.gz
    ${ANTSPATH}/ThresholdImage 2 $malf6 $prior $j $j 1 0
    ${ANTSPATH}/SmoothImage 2 $prior 1 $prior
  done

${ANTSPATH}/ImageMath 2 ${OUT_DIR}/prior1.nii.gz max ${OUT_DIR}/prior1.nii.gz $antsCtCsfPrior

# subtract out csf prior from all other priors

prior1=${OUT_DIR}/prior1.nii.gz
for(( j=2; j<=6; j++ ));
  do
    prior=${OUT_DIR}/prior${j}.nii.gz
    ${ANTSPATH}/ImageMath 2 $prior - $prior $prior1
    ${ANTSPATH}/ThresholdImage 2 $prior $tmp 0 1 1 0
    ${ANTSPATH}/ImageMath 2 $prior m $prior $tmp
  done

rm $tmp

echo "Priors are cooked.  They can be found in ${OUT_DIR}"

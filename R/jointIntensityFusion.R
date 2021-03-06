#' joint intensity fusion
#'
#' Estimates an image from another set of images - intensity generalization of joint label fusion.  Search radius used only when employing labels - WIP to speed it up.
#'
#' @param targetI antsImage to be approximated
#' @param targetIMask mask with value 1
#' @param atlasList list containing antsImages
#' @param beta weight sharpness, default to 2
#' @param rad neighborhood radius, default to 4
#' @param labelList list containing antsImages
#' @param doscale scale neighborhood intensities
#' @param doNormalize normalize each image range to 0, 1
#' @param maxAtlasAtVoxel min/max n atlases to use at each voxel
#' @param rho ridge penalty increases robustness to outliers but also
#'   makes image converge to average
#' @param useSaferComputation slower but more error checking
#' @param usecor employ correlation as local similarity
#' @param rSearch radius of search, default is 2
#' @param boundary.condition one of 'image' 'mean' 'NA'
#' @param segvals list of labels to expect
#' @param includezero boolean - try to predict the zero label
#' @return approximated image, segmentation and probabilities
#' @author Brian B. Avants, Hongzhi Wang, Paul Yushkevich
#' @keywords fusion, template
#' @examples
#'
#' set.seed(123)
#' ref<-antsImageRead( getANTsRData("r16"), 2)
#' ref<-resampleImage(ref,c(50,50),1,0)
#' ref<-iMath(ref,"Normalize")
#' mi<-antsImageRead( getANTsRData("r27"),  2)
#' mi2<-antsImageRead( getANTsRData("r30") ,2)
#' mi3<-antsImageRead( getANTsRData("r62") ,2)
#' mi4<-antsImageRead( getANTsRData("r64") ,2)
#' mi5<-antsImageRead( getANTsRData("r85") ,2)
#' refmask<-getMask(ref)
#' refmask<-iMath(refmask,"ME",2) # just to speed things up
#' ilist<-list(mi,mi2,mi3,mi4,mi5)
#' seglist<-list()
#' for ( i in 1:length(ilist) )
#'  {
#'  ilist[[i]]<-iMath(ilist[[i]],"Normalize")
#'  mytx<-antsRegistration(fixed=ref , moving=ilist[[i]] ,
#'    typeofTransform = c("Affine") )
#'  mywarpedimage<-antsApplyTransforms(fixed=ref,moving=ilist[[i]],
#'    transformlist=mytx$fwdtransforms)
#'  ilist[[i]]=mywarpedimage
#'  seg<-kmeansSegmentation( ilist[[i]], k=3, kmask = refmask)
#'  seglist[[i]]<-seg$segmentation
#'  }
#' r<-2
#' d<-2
#' pp<-jointIntensityFusion(ref,refmask,ilist, rSearch=0,
#'   labelList=seglist, rad=rep(r,d) )
#'
#' @export jointIntensityFusion
jointIntensityFusion <- function( targetI, targetIMask, atlasList,
  beta=4, rad=NA, labelList=NA, doscale = TRUE,
  doNormalize=TRUE, maxAtlasAtVoxel=c(1,Inf), rho=0.01, # debug=F,
  useSaferComputation=FALSE, usecor=FALSE, boundary.condition='mean',
  rSearch=2, segvals=NA, includezero=FALSE )
{
  haveLabels=FALSE
  BC=boundary.condition
  if ( !( all( is.na(labelList) ) ) )
    {
    segmat<-imageListToMatrix( labelList, targetIMask )
    segmatSearch<-segmat
    haveLabels=TRUE
    if ( all( is.na(segvals) ) )
      {
      segvals<-c(sort( unique( as.numeric(segmat)) ))
      if ( includezero )
        if ( ! ( 0 %in% segvals ) ) segvals<-c(0,segvals)
      if ( !includezero )
        segvals<-segvals[  segvals != 0 ]
      }
    }
  dim<-targetI@dimension
  if ( doNormalize )
    {
    for ( i in atlasList ) imageMath(dim,i,"Normalize",i)
    imageMath(dim,targetI,"Normalize",targetI)
    }
  if ( all(is.na(rad)) ) rad<-rep(3,dim)
  n<-1
  for ( k in 1:length(rad)) n<-n*(rad[k]*2+1)
  wmat<-t(replicate(length(atlasList), rep(0.0,n) ) )
  matcenter<-round(n/2)+1
  intmat<-wmat
  targetIvStruct<-getNeighborhoodInMask(targetI,
    targetIMask,rad,boundary.condition=BC,spatial.info=T)
  targetIv<-targetIvStruct$values
  indices<-targetIvStruct$indices
  targetIvStruct<-getNeighborhoodInMask(targetI,
    targetIMask,rep(rSearch,dim),boundary.condition=BC,spatial.info=T)
  offsets<-targetIvStruct$offsets
  rm(targetIvStruct)
  if ( doscale ) targetIv<-scale(targetIv)
  newmeanvec<-rep(0,ncol(targetIv))
  m<-length(atlasList)
  onev<-rep(1,m)
  weightmat<-matrix( rep(0, m*ncol(targetIv) ), nrow=m )
  ct<-1
  natlas<-length(atlasList)
  atlasLabels<-1:natlas
  maxSimImg<-rep(0,ncol(targetIv))
  if ( maxAtlasAtVoxel[2] > natlas ) maxAtlasAtVoxel[2]<-natlas
  progress <- txtProgressBar(min = 0,
                max = ncol(targetIv), style = 3)
  badct<-0
  basewmat<-t(replicate(length(atlasList), rep(0.0,n) ) )
  for ( voxel in 1:ncol(targetIv) )
    {
    zsd<-rep(1,natlas)
    wmat<-basewmat
    targetint<-targetIv[,voxel]
    for ( ct in 1:natlas)
      {
      # is this a BUG/FIXME?
      # see antsImage_GetNeighborhood
      myoff<-rep(0,dim)
      cent<-indices[voxel,]+1
      v<-getNeighborhoodAtVoxel(atlasList[[ct]],cent,rad)$values
      intmat[ct,]<-v
      # find best local region in this atlas
      # just needs an input vector, an input image and a radius
      # outputs the best offset ...
      if ( haveLabels & rSearch > 0 )
      {
      bestmatch<-Inf
      for ( offind in 1:nrow(offsets) )
        {
        cent2<-cent+offsets[offind,]
        tv<-(getNeighborhoodAtVoxel(atlasList[[ct]],cent2,rad)$values)
        sdv<-sd(tv)
        if ( sdv > 0 )
          {
          tv=( tv - mean(tv) )/sdv
          locor<-(-1.0 * sum(targetint*tv) )
          if ( locor < bestmatch )
            {
            v=tv
            bestmatch<-locor
            myoff<-offsets[offind,]
            if ( dim == 2 & haveLabels )
              segval<-getPixels(labelList[[ct]],cent2[1],cent2[2])
            if ( dim == 3 & haveLabels )
              segval<-getPixels(labelList[[ct]],cent2[1],cent2[2],cent2[3])
            if ( haveLabels ) segmatSearch[ct,voxel]<-segval
            }
          }
        }
      }
      sdv<-sd(v)
      if ( sdv == 0 ) {
        zsd[ct]<-0
        sdv<-1
        }
      if ( doscale ) {
        v<-( v - mean(v))/sdv
        }
      if ( !usecor )
        wmat[ct,]<-(v-targetint)
      else {
        ip<- ( v * targetint )
        wmat[ct,]<-( ip*(-1.0))
        }
      } # for all atlases
    if ( maxAtlasAtVoxel[2] < natlas ) {
      ords<-order(rowMeans(abs(wmat)))
      inds<-maxAtlasAtVoxel[1]:maxAtlasAtVoxel[2]
      zsd[ ords[-inds] ]<-0
      }
    if ( sum(zsd) > (2) )
      {
      wmat<-wmat[zsd==1,]
      cormat<-( wmat %*% t(wmat) )
      cormatnorm<-norm(cormat,"F")
      corrho<-cormatnorm*rho
#      cormat<-cor(t(wmat)) # more stable wrt outliers
      if ( useSaferComputation ) # safer computation
      {
      tempf<-function(betaf)
        {
        invmat<-solve( cormat + diag(ncol(cormat))*corrho )^betaf
        onev<-rep(1,sum(zsd))
        wts<-invmat %*% onev / ( sum( onev * invmat %*% onev ))
        return(wts)
        }
      wts<-tryCatch( tempf(beta),
          error = function(e)
            {
            szsd<-sum(zsd)
            wts<-rep(1.0/szsd,szsd)
            return( wts )
            }
        )
      } else {
        invmat<-solve( cormat + diag(ncol(cormat))*corrho )^beta
        onev<-rep(1,sum(zsd))
        wts<-invmat %*% onev / ( sum( onev * invmat %*% onev ))
      }
      if ( ! is.na( mean(wts)) ) {
        weightmat[zsd==1,voxel]<-wts
        maxSimImg[ voxel ]<-atlasLabels[zsd==1][  which.max(wts) ]
        newmeanvec[voxel]<-(intmat[zsd==1,matcenter] %*% wts)[1]
      } else badct<-badct+1
      if ( FALSE ) {
        print("DEBUG MODE")
        print(maxAtlasAtVoxel)
            return(
                list(voxel=voxel,
                     wts=wts,intmat=intmat,
                     wmat=wmat,cormat=cormat, pvox=newmeanvec[voxel],
                     zsd=zsd,intmatc=intmat[zsd==1,matcenter])
                )
              }
      if ( voxel %% 500 == 0 ) {
            setTxtProgressBar( progress, voxel )
        }
    }
  }
  close( progress )
  newimg<-makeImage(targetIMask,newmeanvec)
  maxSimImg<-makeImage(targetIMask,maxSimImg)
  segimg<-NA
  probImgList<-NA
  if ( !( all( is.na(labelList) ) ) )
    {
    segvec<-rep( 0, ncol(segmat) )
    probImgList<-list()
    probImgVec<-list()
    for ( p in 1:length(segvals) )
      probImgVec[[p]]<-rep(0,ncol(segmat))
    for ( voxel in 1:ncol(segmat) )
      {
      probvals<-rep(0,length(segvals))
      segsearch<-segmatSearch[,voxel]
      if  ( sd(segsearch) > 0 )
      {
        for ( p in 1:length(segvals))
        {
        ww<-which( segsearch==segvals[p] )
#          &  weightmat[  , voxel ] > 0 )
          if ( length(ww) > 0 )
            {
            probvals[p]<-sum((weightmat[ ww , voxel ]),na.rm=T)
            }
        }
      probvals<-probvals/sum(probvals)
      } else {
        probvals[ which(segsearch[1]==segvals) ]<-1
      }
      for ( p in 1:length(segvals))
        probImgVec[[p]][voxel]<-probvals[p]
      k<-which(probvals==max(probvals,na.rm=T))
        segvec[voxel]=segvals[ k ]
    }
    for ( p in 1:length(segvals) )
      probImgList[[p]]<-makeImage( targetIMask, probImgVec[[p]] )
    segimg<-makeImage(targetIMask,segvec)
    # 1st probability is background i.e. 0 label
    probImgList<-probImgList[2:length(probImgList)]
    }
  return( list( predimg=newimg, segimg=segimg,
    localWeights=weightmat, probimgs=probImgList,
    maxSimImg=maxSimImg, badct=badct  ) )
}

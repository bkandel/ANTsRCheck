#' Label multivariate components by an anatomical coordinate system.
#'
#' This function will provide a mapping that labels the list of input images
#' and each of their blobs.
#'
#' Uses getTemplateCoordinates as a sub-routine.
#'
#' TBN
#'
#' @param imageSetToBeLabeledIn a template paired with (most likely) the output
#' of a multivariate sparse decomposition or (alternatively) could be just a
#' statistical map with zeroes in non-interesting areas
#' @param templateWithLabels e..g the mni image and brodmann label set
#' @param labelnames a list of names for the labels
#' @param outprefix if output to a file, provide file prefix
#' @param convertToTal bool, return talairach coordinates
#' @param pvals the already computed pvalue for each component
#' @param threshparam for pvals
#' @param clustparam for clusters
#' @param identifier unique ID for this study
#' @return The output point coordinates are in approximate Talairach / MNI (or
#' whatever) template space.
#' @author Avants, BB
#' @keywords Talairach, Template, Coordinates
#' @examples
#'
#' \dontrun{
#'  tem<-antsImageRead( getANTsRData("ch2") )
#'  temlab<-antsImageRead( getANTsRData("ch2b")  )
#'  temlab2<-antsImageRead( getANTsRData("ch2a")  )
#'  # try getANTsRData if you have www access
#'  mymni<-list( antsImageRead(getANTsRData("mni"),3),
#'        antsImageRead(getANTsRData("mnib"),3),
#'        antsImageRead(getANTsRData("mnia"),3) )
#'  mytem<-list( smoothImage(tem,3) ,temlab,temlab2)
#'  # mynetworkdescriptor<-getMultivariateTemplateCoordinates(
#'  #  mytem, mymni , convertToTal = TRUE , pvals=c(0.01,0.05) )
#' }
#'
#' @export getMultivariateTemplateCoordinates
getMultivariateTemplateCoordinates <- function(
  imageSetToBeLabeledIn,
  templateWithLabels,
  labelnames = NA,
  outprefix = NA,
  convertToTal = FALSE,
  pvals = NA,
  threshparam = 1,
  clustparam = 250,
  identifier ) {

  # this function is similar to getTemplateCoordinates however we need to get the
  # coordinates for each of the entries in imageSetToBeLabeled where coordinates
  # come from each subcomponent of the image in imageSetToBeLabeled pseudo-code: 1.
  # transform template to talairach 2. label the multivariate component image by
  # its generic Talairach position i.e. L/R, S/I, A/P --- information needed for
  # this is given by getTemplateCoordinates 3. split each image into its sub
  # components via image2ClusterImages 4. get coordinates for each sub-component
  # image 5. append these coordinates under the output from step 2 6. return
  # something e.g. a table ....

  if (missing(identifier)) {
    identifier <- c(1:(length(imageSetToBeLabeledIn) - 1))
  }
  if (is.na(pvals[1])) {
    pvals <- rep(NA, length(imageSetToBeLabeledIn) - 1)
  }
  myout <- NA
  talregions <- rep(NA, length(imageSetToBeLabeledIn) - 1)
  mytemplate <- imageSetToBeLabeledIn[[1]]
  for (x in 2:length(imageSetToBeLabeledIn)) {
    img <- imageSetToBeLabeledIn[[x]]
    threshimg <- antsImageClone(img)
    thresh <- 1/length(as.array(threshimg))
    imageMath(threshimg@dimension, threshimg, "abs", threshimg)
    # threshimg[ threshimg > (.Machine$double.eps*2) ]<-1
    meanval <- mean(threshimg[threshimg > (.Machine$double.eps * 2)])
    sdval <- sd(threshimg[threshimg > (.Machine$double.eps * 2)])
    threshval <- (meanval - sdval * threshparam)
    if (threshval < (.Machine$double.eps * 2))
      threshval <- (.Machine$double.eps * 2)
    threshimg[threshimg > threshval] <- 1
    threshimg[threshimg <= threshval] <- 0
    imageSetToBeLabeled <- lappend(list(mytemplate), threshimg)
    temp <- getTemplateCoordinates(imageSetToBeLabeled, templateWithLabels, labelnames,
      outprefix, convertToTal)
    talRegion <- ""
    if (temp$templatepoints$x < 0)
      talRegion <- paste(talRegion, "L", sep = "") else talRegion <- paste(talRegion, "R", sep = "")
    if (temp$templatepoints$y > 0)
      talRegion <- paste(talRegion, "A", sep = "") else talRegion <- paste(talRegion, "P", sep = "")
    if (temp$templatepoints$z < 0)
      talRegion <- paste(talRegion, "S", sep = "") else talRegion <- paste(talRegion, "I", sep = "")
    talregions[x - 1] <- talRegion
    clust <- labelClusters(threshimg, clustparam)
    imageSetToBeLabeled <- lappend(list(mytemplate), clust)
    temp2 <- getTemplateCoordinates(imageSetToBeLabeled, templateWithLabels,
      labelnames, outprefix, convertToTal)
    if (x == 2) {
      myout <- data.frame(NetworkID = paste("N", identifier[1], "_omnibus",
        sep = ""), temp$templatepoints, pval = pvals[x - 1])
      subnet <- data.frame(NetworkID = rep(paste("N", identifier[1], "_node",
        sep = ""), nrow(temp2$templatepoints)), temp2$templatepoints, pval = rep(NA,
        nrow(temp2$templatepoints)))
      myout <- rbind(myout, subnet)
    } else {
      pre <- paste("N", identifier[x - 1], sep = "")
      mynextout <- data.frame(NetworkID = paste(pre, "_omnibus", sep = ""),
        temp$templatepoints, pval = pvals[x - 1])
      subnet <- data.frame(NetworkID = rep(paste(pre, "_node", sep = ""), nrow(temp2$templatepoints)),
        temp2$templatepoints, pval = rep(NA, nrow(temp2$templatepoints)))
      myout <- rbind(myout, mynextout)
      myout <- rbind(myout, subnet)
    }
  }
  return(list(networks = myout, myLabelsInTemplateSpace = temp$myLabelsInTemplateSpace,
    myImageInTemplateSpace = temp$myImageInTemplateSpace))
}

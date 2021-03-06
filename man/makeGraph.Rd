% Generated by roxygen2 (4.1.0): do not edit by hand
% Please edit documentation in R/makeGraph.R
\name{makeGraph}
\alias{makeGraph}
\title{Simple function to create and measure a graph from a square input matrix.}
\usage{
makeGraph(mat, graphdensity = 1, communityMethod = NA,
  getEfficiency = FALSE)
}
\arguments{
\item{mat}{input matrix}

\item{graphdensity}{fraction of edges to keep}

\item{communityMethod}{see igraph's community detection}

\item{getEfficiency}{boolean, this is slow to compute}
}
\value{
a named list is output including the graph object, adjacency matrix
and several graph metrics
}
\description{
Creates an igraph object from a square input correlation matrix - only
positive correlations are used.  Based on the graph.adjacency function of
igraph.  gplot is helpful for visualization.
}
\examples{
\dontrun{
mat <- matrix(c(rep(1,100)),ncol=10)
gobj<-makeGraph( mat )
mat <- matrix(  c( 1, 0.5, 0.2, -0.1, 1, 0.3, -0.2, 0.6, 1 ) , ncol= 3 )
gobj<-makeGraph( mat , 0.5 )
# gplot( gobj$adjacencyMatrix ) # need sna library for this
}
}
\author{
Avants BB
}


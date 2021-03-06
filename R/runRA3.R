#' Run RA3 for integrative analysis of scATAC-seq data
#'
#' RA3 refers to Reference-guided Approach for the Analysis of scATAC-seq data. It can simultaneously incorporate shared biological variation from reference data and identify distinct subpopulations, and thus achieves superior performance to existing methods in comprehensive experiments.
#'
#' @param sc_data scATAC-seq count matrix, the rows should refer to features/regions and columns refer to cells.
#' @param ref_data reference data matrix, the columns should refer to features/regioins and rows refer to observations.
#' @param K2 the number of components in RA3's second part, the default value is K2 = 5.
#' @param K3 the number of components in RA3's third part, the default value is K3 = 5.
#' @return A list containing the following components:
#' \item{H}{the extracted latent features H.}
#' \item{W}{the estimated matrix of parameter matrix W.}
#' \item{Beta}{the estimated covariance parameter vector \eqn{\beta}.}
#' \item{Gamma}{the estimated indicator matrix \eqn{\Gamma}.}
#' \item{A}{the estimated precision matrix A.}
#' \item{sigma_s}{the estimated \eqn{\sigma^2}.}
#' \item{lgp}{the largest log posterior value when EM algorithm converges.}
#' @examples
#' result <- runRA3(sc_example, reference_example)
#' result <- runRA3(sc_example, reference_example, 10, 5)
#' @importFrom pracma repmat
#' @importFrom irlba irlba
#' @export

runRA3 <- function(sc_data, ref_data, K2 = 5, K3 = 5){
  Y <- sc_data # p by n
  bulk_mat <- ref_data # n_bulk by p

  # Data Preprocessing
  # TF-IDF
  nfreqs = Y / pracma::repmat(apply(Y, 2, sum), dim(Y)[1], 1)
  Y_mat = nfreqs * t(pracma::repmat(log(1 + dim(Y)[2] / rowSums(Y)), dim(Y)[2], 1))

  # Calculate Initialization Value for the Algorithm
  # pca for reference
  K1 <- nrow(bulk_mat)-1
  
  bulk_mat_cent <- bulk_mat - repmat(apply(bulk_mat, 2, mean),nrow(bulk_mat),1)
  pca_bulk <-  irlba::irlba(bulk_mat_cent, nv = K1)
  coeff <- pca_bulk$v
  score <- pca_bulk$u %*% diag(pca_bulk$d)


  # Standardize
  p <- nrow(Y)
  n <- ncol(Y)


  latent_h <- t(coeff) %*% Y_mat
  V_beta <- sqrt(apply(t(latent_h),2,var))
  init_V <- pracma::repmat(V_beta, p, 1) * coeff

  # Good Start of K2 Component
  residual <- Y_mat - coeff %*% (t(coeff) %*% Y_mat)
  res_pca <- irlba::irlba(t(residual), nv = K2)
  coeff_res <- res_pca$v
  score_res <- res_pca$u %*% diag(res_pca$d)
  score_res_rotate <- varimax(score_res[ ,1:K2])
  RM <- score_res_rotate$rotmat
  coeff_res_rotate <- coeff_res[ ,1:K2] %*% RM # p by k
  score_reconst_rotate <- t(residual) %*% coeff_res_rotate # n by k
  W2_ini <- coeff_res_rotate %*% diag(sqrt(apply(score_reconst_rotate, 2, var)))

  # Good Start of Sigma
  center_Y_stand <- Y_mat - t(rep(1, ncol(Y_mat)) %*% t(rowMeans(Y_mat)))
  residual_stand = center_Y_stand - coeff %*% (t(coeff) %*% center_Y_stand)
  res_stand_pca <- irlba::irlba(t(residual_stand), nv = 20)
  coeff_res_stand <- res_stand_pca$v
  score_res_stand <- res_stand_pca$u %*% diag(res_stand_pca$d)
  score_rotate2 <- varimax(score_res_stand[ ,1:20])
  RM_stand <-  score_rotate2$rotmat
  coeff_stand_rotate <- coeff_res_stand[, 1:20] %*% RM_stand
  score_reconst_stand_rotate = t(residual_stand) %*% coeff_stand_rotate

  res_final <- residual_stand - coeff_stand_rotate %*% t(score_reconst_stand_rotate)
  epsilon_stard = res_final - t(rep(1, ncol(res_final)) %*% t(rowMeans(res_final)))
  sigma_setting = sum(epsilon_stard^2)/(n*p)

  # Parameters Setting
  K <- K1 + K2 + K3
  para_num <- p * K


  # Initialization
  W1_ini <- init_V[ ,1:K1]
  W_PCA <- cbind(W1_ini, W2_ini[ ,1:K2], matrix(rnorm(p*K3,0,1), p, K3))
  A_PCA <- diag(c(rep(1,K2), rep(1,K3)))
  Gamma_PCA <- matrix(rep(1,K*n), K, n)
  Gamma_PCA[(K1+1):(K2+K1), ] <-  matrix(rep(0, K2*n), K2, n)

  # Run
   result <- RA3_EM(Y_mat,K1,K2,K3,Gamma_PCA,A_PCA,W_PCA,sigma_setting)
   return(result)
  }

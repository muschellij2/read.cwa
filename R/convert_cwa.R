get_hdr = function(file, verbose = TRUE) {
  hdr = NULL
  if (requireNamespace("GGIRread", quietly = TRUE)) {
    hdr = GGIRread::readAxivity(file, start = 0, end = 10, progressBar = verbose,
                          desiredtz = "UTC")
    hdr = hdr$header
  }
  hdr
}
#' Convert a CWA activity file to a CSV
#' @param file input CWA file
#' @param outfile output CSV file
#' @param verbose print diagnostic messages
#' @param xyz_only read only time and X/Y/Z columns
#' @return Name of output CSV file
#' @export
#' @useDynLib read.cwa , .registration=TRUE
#' @examples
#' gz_file = system.file("extdata", "ax3_testfile.cwa.gz", package = "read.cwa")
#' file = R.utils::gunzip(gz_file, temporary = TRUE, remove = FALSE, overwrite = TRUE)
#' out = read_cwa(file)
#' out = read_cwa(file, xyz_only = FALSE)
convert_cwa <- function(file, outfile = tempfile(fileext = ".csv"),
                        xyz_only = TRUE,
                        verbose = TRUE) {
  file = path.expand(file)
  file = normalizePath(file, winslash = "/", mustWork = TRUE)
  unlink_file = FALSE
  for (ext in c("bz2", "gz", "xz")) {
    if (R.utils::isCompressedFile(
      file, method = "extension",
      ext = ext,
      fileClass = "")) {
      FUN = switch(ext,
                   gz = gzfile,
                   xz = xzfile,
                   bz2 = bzfile
      )
      file = R.utils::decompressFile(
        file,
        destname = tempfile(fileext = ".cwa"),
        temporary = TRUE,
        overwrite = TRUE,
        ext = ext,
        FUN = FUN,
        remove = FALSE)
      unlink_file = TRUE
    }
  }
  if (unlink_file) {
    on.exit(unlink(file, recursive = TRUE))
  }
  outfile = as.character(outfile)
  stopifnot(nchar(outfile) > 0)
  args = c(file,  outfile)

  result = .Call("convert_cwa_",  args[1], args[2],
                 as.integer(xyz_only),
                 as.integer(verbose),
                 PACKAGE = "read.cwa")
  hdr = get_hdr(file, verbose = verbose)
  L = list(file = result)
  L$header = hdr
  L
}

#' @rdname convert_cwa
#' @export
read_cwa_csv = function(file, xyz_only = TRUE, verbose = TRUE) {
  header = NULL
  if (is.list(file) && all(c("file", "header") %in% names(file))) {
    header = file$header
    file = file$file
  }
  default = readr::col_double()
  event_col = readr::col_character()
  if (xyz_only) {
    default = readr::col_skip()
    event_col = readr::col_skip()
  }
  col_spec = readr::cols(
    time = readr::col_datetime(format = ""),
    .default = default,
    X = readr::col_double(),
    Y = readr::col_double(),
    Z = readr::col_double(),
    events = event_col
  )
  cnames = c("time", "X", "Y", "Z",
             "light", "temperature", "battery",
             "battery_voltage",
             "battery_percentage",
             "battery_relative",
             "events")
  if (xyz_only) {
    col_spec$cols$events = NULL
    cnames = c("time", "X", "Y", "Z")
  }
  x = readr::read_csv(
    file,
    col_names = cnames,
    col_types = col_spec,
    progress = verbose
  )
  attr(x, "header") = header
  x
}

#' @rdname convert_cwa
#' @export
read_cwa <- function(file, outfile = tempfile(fileext = ".csv"),
                     xyz_only = TRUE,
                     verbose = TRUE) {
  if (verbose) {
    message("Converting the CWA to CSV")
  }
  csv = convert_cwa(file, outfile = outfile, xyz_only = xyz_only,
                    verbose = verbose)
  hdr = csv$header
  csv_file = csv$file
  if (verbose) {
    message(paste0("Reading in the CSV: ", csv_file))
  }
  L = list(
    data = read_cwa_csv(csv_file, xyz_only = xyz_only, verbose = verbose),
    header = hdr)
  if (!is.null(hdr$frequency)) {
    L$freq = hdr$frequency
  }
  if (length(hdr$accrange) > 0) {
    arange =try({unique(abs(as.numeric(hdr$accrange)))})
    if (!inherits(arange, "try-error")) {
      attr(L$data, "dynamic_range") = c(-arange, arange)
    }
  }
  class(L) = "AccData"
  L
}

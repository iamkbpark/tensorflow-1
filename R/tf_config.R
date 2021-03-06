

tf_config <- function() {
  .tf_config
}

tf_discover_config <- function() {

  # create a list of possible python versions to bind to
  python_versions <- character()

  # look for environment variable
  tensorflow_python <- tensorflow_python()
  if (!is.null(tensorflow_python())) {
    if (tensorflow_python$exists)
      python_versions <- c(python_versions, tensorflow_python$python)
    else
      warning("Specified TENSORFLOW_PYTHON '", tensorflow_python$python, "' does not exist.")
  }

  # look on system path
  python <- Sys.which("python")
  if (nzchar(python))
    python_versions <- c(python_versions, python)

  # provide other common locations
  if (is_windows()) {
    extra_versions <- windows_registry_python_versions()
  } else {
    extra_versions <- c(
      path.expand("~/tensorflow/bin/python"), # virtualenv
      "/usr/local/bin/python",
      "/opt/python/bin/python",
      "/opt/local/python/bin/python",
      "/usr/bin/python3",
      "/usr/local/bin/python3",
      "/opt/python/bin/python3",
      "/opt/local/python/bin/python3",
      path.expand("~/anaconda/envs/tensorflow/bin/python"),
      path.expand("~/anaconda/bin/python"),
      path.expand("~/anaconda3/envs/tensorflow/bin/python"),
      path.expand("~/anaconda3/bin/python")
    )
  }

  # filter locations by existence
  python_versions <- unique(c(python_versions, extra_versions))
  python_versions <- python_versions[file.exists(python_versions)]

  # scan until we find a version of tensorflow that meets
  # qualifying conditions
  for (python_version in python_versions) {
    config <- tf_python_config(python_version, python_versions)
    if (!is.null(config$tensorflow) && !is_incompatible_arch(config)) {
      return(config)
    }
  }

  # no version of tf found, return first if we have it or NULL
  if (length(python_versions) >= 1)
    return(tf_python_config(python_versions[[1]], python_versions))
  else
    return(NULL)
}


tf_python_config <- function(python, python_versions) {

  # collect configuration information
  config_script <- system.file("config/config.py", package = "tensorflow")
  config <- system2(command = python, args = paste0('"', config_script, '"'), stdout = TRUE)
  status <- attr(config, "status")
  if (!is.null(status)) {
    errmsg <- attr(config, "errmsg")
    stop("Error ", status, " occurred running ", python, " ", errmsg)
  }

  config <- read.dcf(textConnection(config), all = TRUE)

  # get the full textual version and the numeric version, check for anaconda
  version_string <- config$Version
  version <- config$VersionNumber
  anaconda <- grepl("continuum", tolower(version_string)) || grepl("anaconda", tolower(version_string))
  architecture <- config$Architecture

  # determine the location of libpython (see also # https://github.com/JuliaPy/PyCall.jl/blob/master/deps/build.jl)
  if (is_windows()) {
    # note that 'prefix' has the binary location and 'py_version_nodot` has the suffix`
    python_libdir <- dirname(python)
    libpython <- file.path(python_libdir, paste0("python", gsub(".", "", version, fixed = TRUE), ".dll"))
  } else {
    # (note that the LIBRARY variable has the name of the static library)
    python_libdir_config <- function(var) {
      python_libdir <- config[[var]]
      ext <- switch(Sys.info()[["sysname"]], Darwin = ".dylib", Windows = ".dll", ".so")
      libpython <- file.path(python_libdir, paste0("libpython" , version, c("", "m"), ext))
      libpython_exists <- libpython[file.exists(libpython)]
      if (length(libpython_exists) > 0)
        libpython_exists[[1]]
      else
        libpython[[1]]
    }
    libpython <- python_libdir_config("LIBPL")
    if (!file.exists(libpython))
      libpython <- python_libdir_config("LIBDIR")
  }

  # determine PYTHONHOME
  pythonhome <- config$PREFIX
  if (!is_windows())
    pythonhome <- paste(pythonhome, config$EXEC_PREFIX, sep = ":")


  as_numeric_version <- function(version) {
    version <- clean_tf_version(version)
    numeric_version(version)
  }

  # check for numpy and tensorflow
  if (!is.null(config$NumpyPath))
    numpy <- list(path = config$NumpyPath,
                  version = as_numeric_version(config$NumpyVersion))
  else
    numpy <- NULL
  if (!is.null(config$TensorflowPath))
    tensorflow <- config$TensorflowPath
  else
    tensorflow <- NULL

  # check for virtualenv activate script
  activate_this <- file.path(dirname(python), "activate_this.py")
  if (file.exists(activate_this))
    virtualenv_activate <- activate_this
  else
    virtualenv_activate <- ""

  # return config info
  structure(class = "tf_config", list(
    python = python,
    libpython = libpython,
    pythonhome = pythonhome,
    virtualenv_activate = virtualenv_activate,
    version_string = version_string,
    version = version,
    architecture = architecture,
    anaconda = anaconda,
    numpy = numpy,
    tensorflow = tensorflow,
    python_versions = python_versions
  ))

}

#' @export
str.tf_config <- function(object, ...) {
  x <- object
  out <- ""
  out <- paste0(out, "python:         ", x$python, "\n")
  out <- paste0(out, "libpython:      ", x$libpython, ifelse(file.exists(x$libpython), "", "[NOT FOUND]"), "\n")
  out <- paste0(out, "pythonhome:     ", x$pythonhome, "\n")
  if (nzchar(x$virtualenv_activate))
    out <- paste0(out, "virtualenv:     ", x$virtualenv_activate, "\n")
  out <- paste0(out, "version:        ", x$version_string, "\n")
  if (is_windows())
    out <- paste0(out, "Architecture:   ", x$architecture, "\n")
  if (!is.null(x$numpy)) {
    out <- paste0(out, "numpy:          ", x$numpy$path, "\n")
    out <- paste0(out, "numpy_version:  ", as.character(x$numpy$version), "\n")
  } else {
    out <- paste0(out, "numpy:           [NOT FOUND]\n")
  }
  if (!is.null(x$tensorflow)) {
    out <- paste0(out, "tf:             ", x$tensorflow, "\n")
  } else {
    out <- paste0(out, "tf:              [NOT FOUND]\n")
  }
  if (length(x$python_versions) > 1) {
    out <- paste0(out, "\npython versions found: \n")
    python_versions <- paste0(" ", x$python_versions, collapse = "\n")
    out <- paste0(out, python_versions, sep = "\n")
  }
  out
}

#' @export
print.tf_config <- function(x, ...) {
 cat(str(x))
}


is_windows <- function() {
  identical(.Platform$OS.type, "windows")
}

is_osx <- function() {
  Sys.info()["sysname"] == "Darwin"
}


clean_tf_version <- function(tf_version) {
  gsub("\\.$", "", gsub("[A-Za-z_]+", "", tf_version))
}

tensorflow_python <- function() {

  # determine the location of python
  tensorflow_python <- Sys.getenv("TENSORFLOW_PYTHON", unset = NA)
  if (!is.na(tensorflow_python)) {

    # normalize trailing slash and expand
    tensorflow_python <- gsub("[\\/]+$", "", tensorflow_python)
    tensorflow_python <- path.expand(tensorflow_python)

    # check for existence
    if (!utils::file_test("-d", tensorflow_python) &&
        !utils::file_test("-f", tensorflow_python)) {
      list(
        python = tensorflow_python,
        exists = FALSE
      )
    } else {

      # append binary if it's a directory
      if (utils::file_test("-d", tensorflow_python))
        tensorflow_python <- file.path(tensorflow_python, "python")

      # append .exe if necessary on windows
      if (is_windows() && (!endsWith(tolower(tensorflow_python), ".exe")))
        tensorflow_python <- paste0(tensorflow_python, ".exe")

      # return
      list(
        python = tensorflow_python,
        exists = TRUE
      )
    }


  } else {
    NULL
  }
}

windows_registry_python_versions <- function() {

  read_python_versions <- function(hive,key) {
    versions <- c()
    python_core_key <- tryCatch(utils::readRegistry(
      key = paste0("SOFTWARE\\Python\\", key), hive = hive, maxdepth = 3),
      error = function(e) NULL)

    if (length(python_core_key) > 0) {
      for (version in names(python_core_key)) {
        version_key <- python_core_key[[version]]
        if (is.list(version_key) && !is.null(version_key$InstallPath)) {
          version_dir <- version_key$InstallPath$`(Default)`
          version_dir <- gsub("[\\/]+$", "", version_dir)
          version_exe <- paste0(version_dir, "\\python.exe")
          versions <- c(versions, utils::shortPathName(version_exe))
        }
      }
    }

    versions
  }

  python_core_versions <- c(read_python_versions("HCU", key = "PythonCore"),
                            read_python_versions("HLM", key = "PythonCore"))


  anaconda_versions <- c(read_python_versions("HCU", key = "ContinuumAnalytics"),
                         read_python_versions("HLM", key = "ContinuumAnalytics"))
  if (length(anaconda_versions) > 0) {
    anaconda_envs <- utils::shortPathName(
      file.path(dirname(anaconda_versions), "envs", "tensorflow", "python.exe")
    )
  } else {
    anaconda_envs <- NULL
  }

  c(python_core_versions, anaconda_envs, anaconda_versions)
}

# convert R arch to python arch
python_arch <- function() {
  if (.Platform$r_arch == "i386")
    "32bit"
  else if (.Platform$r_arch == "x64")
    "64bit"
  else
    "Unknown"
}


# check for compatible architecture
is_incompatible_arch <- function(config) {
  if (is_windows()) {
    !identical(python_arch(),config$architecture)
  } else {
    FALSE
  }
}


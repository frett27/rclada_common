
function(ada_add_executables TARGET SRCDIR OUTDIR #[[ targets ]])
# No gpr file is passed as argument, only one must exist at SRCDIR
# TARGET: a target name
# SRCFOLDER: the path to the GPR-containing project
# OUTFOLDER: relative path in SRCFOLDER where the real targets are built
# TARGETS: each executable name built by this project, without path

    ada_priv_expand_srcdir(_srcdir ${SRCDIR})

    # message(STATUS "XXXXXXXXXXXXXXXXXX GPRS: ${ADA_GPR_DIRS}")

    # the target that builds the Ada project and true Ada executables
    add_custom_target(
            ${TARGET}
            ALL # Always, to ensure changes are propagated. At worst, gprbuild will do nothing
            COMMAND_EXPAND_LISTS
            WORKING_DIRECTORY ${_srcdir}
            COMMAND gprbuild
                "-aP$<JOIN:${ADA_GPR_DIRS},;-aP>"
                -p -j0
                --relocate-build-tree=${PROJECT_BINARY_DIR}

            COMMENT "${TARGET} Ada project build target created"
    )

    # This target depends on any messages defined in this same package, if any
    if (TARGET ada_interfaces)
        add_dependencies(${TARGET} ada_interfaces)
    endif()

    # Fake targets (to be indexed by autocompletion) and its replacement
    foreach(EXEC ${ARGN})
        # Fake exec to be able to install an executable target
        add_executable(${EXEC} ${ADA_RESOURCE_DIR}/rclada_fake_target.c)

        # Copy each executable in place
        add_custom_command(
                TARGET ${EXEC}
                POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E remove -f ${PROJECT_BINARY_DIR}/${EXEC}
                COMMAND ${CMAKE_COMMAND} -E copy
                    ${PROJECT_BINARY_DIR}/${OUTDIR}/${EXEC}
                    ${PROJECT_BINARY_DIR}/${EXEC}
                COMMENT "${EXEC} Ada binary put in place"
        )

        # ensure the Ada project is built before so the post-command works
        # make the copy in place after building
        add_dependencies(${EXEC} ${TARGET})

        # must go into "lib" or ros bash completion misses it (duh)
        install(TARGETS     ${EXEC}
                DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/${PROJECT_NAME}/)
    endforeach()

endfunction()


# Generates the Ada and rest of languages messages and sh¡t. Since I was unable to understand
# the CMake macros that do all this or even register successfully the generator, all is redone for Ada.
# [iface files...] [DEPENDENCIES [packages used in iface files...]]
function(ada_add_interfaces)
    set(multiValueArgs DEPENDENCIES)
    cmake_parse_arguments(LOCAL "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

    set(_files ${LOCAL_UNPARSED_ARGUMENTS})

    rosidl_generate_interfaces(${PROJECT_NAME}
        ${_files}
        DEPENDENCIES
        ${LOCAL_DEPENDENCIES})

    find_package(rosidl_generator_ada REQUIRED)

    # Add a target for the generator with the arguments
    add_custom_command(
        OUTPUT ada_ifaces.stamp # Never created, so regenerated every time until I do smthg about this
        COMMAND echo "Running Ada generator for ${LOCAL_UNPARSED_ARGUMENTS}"
        COMMAND ${ADA_GENERATOR} ${_files}
        DEPENDS ${PROJECT_NAME} ${_files} # so the C ones are generated first
        VERBATIM
    )
    
    # Avoid multiple generations by grouping the generator command under a common custom target
    add_custom_target(ada_interfaces ALL
        COMMENT "Custom target for ADA GENERATOR"
        DEPENDS ada_ifaces.stamp
        VERBATIM
    )
endfunction()


function(ada_add_library TARGET SRCDIR GPRFILE)
    ada_priv_expand_srcdir(_srcdir ${SRCDIR})

    add_custom_target(${TARGET}
            ALL
            COMMAND_EXPAND_LISTS

            COMMENT "Building ${GPRFILE} from ${SRCDIR}"
            # build
            COMMAND gprbuild
                -p -j0 -P ${_srcdir}/${GPRFILE}
               "-aP$<JOIN:${ADA_GPR_DIRS},;-aP>"
                --relocate-build-tree=${PROJECT_BINARY_DIR}

            COMMENT "Installing ${GPRFILE} in ${CMAKE_INSTALL_PREFIX}"
            # install
            COMMAND gprinstall
                -f -m -p -P ${_srcdir}/${GPRFILE}
                "-aP$<JOIN:${ADA_GPR_DIRS},;-aP>"
                --relocate-build-tree=${PROJECT_BINARY_DIR}
                --prefix=${CMAKE_INSTALL_PREFIX}

            COMMENT "${GPRFILE} (${_srcdir}) installation complete"
            )

    # This target depends on any messages defined in this same package, if any
    if (TARGET ada_interfaces)
        add_dependencies(${TARGET} ada_interfaces)
    endif()
endfunction()


function(ada_generate_binding TARGET SRCDIR GPRFILE INCLUDE #[[ ARGN ]])
    # Generate corresponding Ada specs, compile it and deploy it
    # TARGET is the desired target name to depend on this
    # SRCDIR is a preexisting ada project prepared to compile in "gen" the generated specs
    # INCLUDE, list (;-separated) of folders to add with -I
    # ARGN, headers to generate

    ada_priv_expand_srcdir(_srcdir ${SRCDIR})

    set(_gen_flag ${_srcdir}/gen/generated)

    add_custom_target(${TARGET}
        ALL
        DEPENDS ${_gen_flag}
        COMMAND_EXPAND_LISTS

        COMMENT "Building ${GPRFILE} Ada project"
        COMMAND gprbuild
            -p -j0 -P ${_srcdir}/${GPRFILE}
            "-aP$<JOIN:${ADA_GPR_DIRS},;-aP>"
            --relocate-build-tree=${PROJECT_BINARY_DIR}
            -cargs "$<$<BOOL:${INCLUDE}>:-I$<JOIN:${INCLUDE},;-I>>"

        # This might need to be separated into a custom script, since it now runs at build time
        COMMENT "Installing ${GPRFILE} Ada project"
        COMMAND gprinstall
            -f -m -p -P ${_srcdir}/${GPRFILE}
            "-aP$<JOIN:${ADA_GPR_DIRS},;-aP>"
            --relocate-build-tree=${PROJECT_BINARY_DIR}
            --prefix=${CMAKE_INSTALL_PREFIX}

        COMMENT "${GPRFILE} (${_srcdir}}) installed"
    )

    # Generate autobinding
    add_custom_command(
            OUTPUT ${_gen_flag}

            COMMAND_EXPAND_LISTS
            WORKING_DIRECTORY ${_srcdir}/gen

            COMMENT "Generating autobinding for project ${GPRFILE}..."
            COMMAND g++
            -fdump-ada-spec-slim
            -C
            "$<$<BOOL:${INCLUDE}>:-I$<JOIN:${INCLUDE},;-I>>"
            ${ARGN}

            COMMAND touch ${_gen_flag}
    )
endfunction()
module Ethon
  class Multi # :nodoc
    # This module contains logic to run a multi.
    module Operations
      # Return the multi handle. Inititialize multi handle,
      # in case it didn't happened already.
      #
      # @example Return multi handle.
      #   multi.handle
      #
      # @return [ FFI::Pointer ] The multi handle.
      def handle
        @handle ||= FFI::AutoPointer.new(Curl.multi_init, Curl.method(:multi_cleanup))
      end

      # Initialize variables.
      #
      # @example Initialize variables.
      #   multi.init_vars
      #
      # @return [ void ]
      def init_vars
        @timeout = ::FFI::MemoryPointer.new(:long)
        @timeval = Curl::Timeval.new
        @fd_read = Curl::FDSet.new
        @fd_write = Curl::FDSet.new
        @fd_excep = Curl::FDSet.new
        @max_fd = ::FFI::MemoryPointer.new(:int)
      end

      # Perform multi.
      #
      # @return [ nil ]
      #
      # @example Perform multi.
      #   multi.perform
      def perform
        Ethon.logger.debug("ETHON: started MULTI")
        while ongoing?
          run
          timeout = get_timeout
          next if timeout == 0
          reset_fds
          set_fds(timeout)
        end
        Ethon.logger.debug("ETHON: performed MULTI")
        nil
      end

      # Prepare multi.
      #
      # @return [ nil ]
      #
      # @example Prepare multi.
      #   multi.prepare
      #
      # @deprecated It is no longer necessary to call prepare.
      def prepare
        Ethon.logger.warn(
          "ETHON: It is no longer necessay to call "+
          "Multi#prepare. Its going to be removed "+
          "in future versions."
        )
      end

      private

      # Return wether the multi still requests or not.
      #
      # @example Return if ongoing.
      #   multi.ongoing?
      #
      # @return [ Boolean ] True if ongoing, else false.
      def ongoing?
        easy_handles.size > 0 || (!defined?(@running_count) || running_count > 0)
      end

      # Get timeout.
      #
      # @example Get timeout.
      #   multi.get_timeout
      #
      # @return [ Integer ] The timeout.
      #
      # @raise [ Ethon::Errors::MultiTimeout ] If getting the timeout fails.
      def get_timeout
        code = Curl.multi_timeout(handle, @timeout)
        raise Errors::MultiTimeout.new(code) unless code == :ok
        timeout = @timeout.read_long
        timeout = 1 if timeout < 0
        timeout
      end

      # Reset file describtors.
      #
      # @example Reset fds.
      #   multi.reset_fds
      #
      # @return [ void ]
      def reset_fds
        @fd_read.clear
        @fd_write.clear
        @fd_excep.clear
      end

      # Set fds.
      #
      # @example Set fds.
      #   multi.set_fds
      #
      # @return [ void ]
      #
      # @raise [ Ethon::Errors::MultiFdset ] If setting the file descriptors fails.
      # @raise [ Ethon::Errors::Select ] If select fails.
      def set_fds(timeout)
        code = Curl.multi_fdset(handle, @fd_read, @fd_write, @fd_excep, @max_fd)
        raise Errors::MultiFdset.new(code) unless code == :ok
        max_fd = @max_fd.read_int
        if max_fd == -1
          sleep(0.001)
        else
          @timeval[:sec] = timeout / 1000
          @timeval[:usec] = (timeout * 1000) % 1000000
          code = Curl.select(max_fd + 1, @fd_read, @fd_write, @fd_excep, @timeval)
          raise Errors::Select.new(::FFI.errno) if code < 0
        end
      end

      # Check.
      #
      # @example Check.
      #   multi.check
      #
      # @return [ void ]
      def check
        msgs_left = ::FFI::MemoryPointer.new(:int)
        while true
          msg = Curl.multi_info_read(handle, msgs_left)
          break if msg.null?
          next if msg[:code] != :done
          easy = easy_handles.find{ |e| e.handle == msg[:easy_handle] }
          easy.return_code = msg[:data][:code]
          Ethon.logger.debug("ETHON:         performed #{easy.log_inspect}")
          delete(easy)
          easy.complete
        end
      end

      # Run.
      #
      # @example Run
      #   multi.run
      #
      # @return [ void ]
      def run
        begin code = trigger end while code == :call_multi_perform
        check
      end

      # Trigger.
      #
      # @example Trigger.
      #   multi.trigger
      #
      # @return [ Symbol ] The Curl.multi_perform return code.
      def trigger
        running_count = FFI::MemoryPointer.new(:int)
        code = Curl.multi_perform(handle, running_count)
        @running_count = running_count.read_int
        code
      end

      # Return number of running requests.
      #
      # @example Return count.
      #   multi.running_count
      #
      # @return [ Integer ] Number running requests.
      def running_count
        @running_count ||= nil
      end
    end
  end
end

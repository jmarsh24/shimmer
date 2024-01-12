# frozen_string_literal: true

module Shimmer
  class FileProxy
    attr_reader :blob_id, :resize, :quality

    delegate :message_verifier, to: :class
    delegate :content_type, :filename, to: :blob

    class << self
      def restore(id)
        blob_id, resize = message_verifier.verified(id)
        new blob_id: blob_id, resize: resize
      end

      def message_verifier
        @message_verifier ||= ApplicationRecord.signed_id_verifier
      end
    end

    def initialize(blob_id:, resize: nil, width: nil, height: nil, quality: nil)
      @blob_id = blob_id
      if !resize && width
        resize = if height
          [width, height]
        else
          [width, nil]
        end
      end
      @resize = resize
      @quality = quality
    end

    def path
      Rails.application.routes.url_helpers.file_path("#{id}.#{file_extension}", locale: nil)
    end

    def url(protocol: Rails.env.production? ? :https : :http)
      Rails.application.routes.url_helpers.file_url("#{id}.#{file_extension}", locale: nil, protocol: protocol)
    end

    def blob
      @blob ||= ActiveStorage::Blob.find(blob_id)
    end

    def resizeable
      resize.present? && blob.content_type.exclude?("svg")
    end

    def variant
      resize_array = process_resize(resize)

      transformation_options = {resize_to_limit: resize_array, format: :avif}
      transformation_options[:quality] = quality if quality

      @variant ||= resizeable ? blob.representation(transformation_options).processed : blob
    end

    def variant_content_type
      resizeable ? "image/avif" : content_type
    end

    def variant_filename
      resizeable ? "#{filename.base}.avif" : filename.to_s
    end

    def file
      @file ||= blob.service.download(variant.key)
    end

    private

    def process_resize(resize)
      return nil unless resize

      if resize.is_a?(String)
        # Split the string and convert to integers. If height is missing, it will be nil
        dimensions = resize.split("x").map { |dim| dim.empty? ? nil : dim.to_i }
        (dimensions.length == 1) ? [dimensions.first, nil] : dimensions
      elsif resize.is_a?(Array)
        resize
      end
    end

    def id
      @id ||= message_verifier.generate([blob_id, resize, quality])
    end

    def file_extension
      resizeable ? "avif" : content_type.split("/").last
    end
  end
end

# PdfBox can decode JPEG 2000 with an optional library this app doesn't include.
-dontwarn com.gemalto.jp2.**
# PdfBox finds parts of itself by name; it's only used for metadata and outlines.
-keep class com.tom_roush.pdfbox.** { *; }

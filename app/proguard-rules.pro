# kotlinx.serialization, Ktor, OkHttp и supabase-kt поставляют собственные consumer-правила.
-dontwarn org.slf4j.**
-dontwarn java.lang.management.**
-dontwarn io.ktor.util.debug.**
-keepattributes *Annotation*, InnerClasses, Signature
-keep,includedescriptorclasses class tj.payvand.core.**$$serializer { *; }
-keepclassmembers class tj.payvand.core.** { *** Companion; }
-keepclasseswithmembers class tj.payvand.core.** { kotlinx.serialization.KSerializer serializer(...); }

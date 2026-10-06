// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'prompt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PromptResponse {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptResponse);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PromptResponse()';
}


}

/// @nodoc
class $PromptResponseCopyWith<$Res>  {
$PromptResponseCopyWith(PromptResponse _, $Res Function(PromptResponse) __);
}


/// Adds pattern-matching-related methods to [PromptResponse].
extension PromptResponsePatterns on PromptResponse {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PromptResponse_PinCode value)?  pinCode,TResult Function( PromptResponse_Passkey value)?  passkey,TResult Function( PromptResponse_Accept value)?  accept,TResult Function( PromptResponse_Deny value)?  deny,TResult Function( PromptResponse_Cancel value)?  cancel,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PromptResponse_PinCode() when pinCode != null:
return pinCode(_that);case PromptResponse_Passkey() when passkey != null:
return passkey(_that);case PromptResponse_Accept() when accept != null:
return accept(_that);case PromptResponse_Deny() when deny != null:
return deny(_that);case PromptResponse_Cancel() when cancel != null:
return cancel(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PromptResponse_PinCode value)  pinCode,required TResult Function( PromptResponse_Passkey value)  passkey,required TResult Function( PromptResponse_Accept value)  accept,required TResult Function( PromptResponse_Deny value)  deny,required TResult Function( PromptResponse_Cancel value)  cancel,}){
final _that = this;
switch (_that) {
case PromptResponse_PinCode():
return pinCode(_that);case PromptResponse_Passkey():
return passkey(_that);case PromptResponse_Accept():
return accept(_that);case PromptResponse_Deny():
return deny(_that);case PromptResponse_Cancel():
return cancel(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PromptResponse_PinCode value)?  pinCode,TResult? Function( PromptResponse_Passkey value)?  passkey,TResult? Function( PromptResponse_Accept value)?  accept,TResult? Function( PromptResponse_Deny value)?  deny,TResult? Function( PromptResponse_Cancel value)?  cancel,}){
final _that = this;
switch (_that) {
case PromptResponse_PinCode() when pinCode != null:
return pinCode(_that);case PromptResponse_Passkey() when passkey != null:
return passkey(_that);case PromptResponse_Accept() when accept != null:
return accept(_that);case PromptResponse_Deny() when deny != null:
return deny(_that);case PromptResponse_Cancel() when cancel != null:
return cancel(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  pinCode,TResult Function( int field0)?  passkey,TResult Function()?  accept,TResult Function()?  deny,TResult Function()?  cancel,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PromptResponse_PinCode() when pinCode != null:
return pinCode(_that.field0);case PromptResponse_Passkey() when passkey != null:
return passkey(_that.field0);case PromptResponse_Accept() when accept != null:
return accept();case PromptResponse_Deny() when deny != null:
return deny();case PromptResponse_Cancel() when cancel != null:
return cancel();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  pinCode,required TResult Function( int field0)  passkey,required TResult Function()  accept,required TResult Function()  deny,required TResult Function()  cancel,}) {final _that = this;
switch (_that) {
case PromptResponse_PinCode():
return pinCode(_that.field0);case PromptResponse_Passkey():
return passkey(_that.field0);case PromptResponse_Accept():
return accept();case PromptResponse_Deny():
return deny();case PromptResponse_Cancel():
return cancel();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  pinCode,TResult? Function( int field0)?  passkey,TResult? Function()?  accept,TResult? Function()?  deny,TResult? Function()?  cancel,}) {final _that = this;
switch (_that) {
case PromptResponse_PinCode() when pinCode != null:
return pinCode(_that.field0);case PromptResponse_Passkey() when passkey != null:
return passkey(_that.field0);case PromptResponse_Accept() when accept != null:
return accept();case PromptResponse_Deny() when deny != null:
return deny();case PromptResponse_Cancel() when cancel != null:
return cancel();case _:
  return null;

}
}

}

/// @nodoc


class PromptResponse_PinCode extends PromptResponse {
  const PromptResponse_PinCode(this.field0): super._();
  

 final  String field0;

/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptResponse_PinCodeCopyWith<PromptResponse_PinCode> get copyWith => _$PromptResponse_PinCodeCopyWithImpl<PromptResponse_PinCode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptResponse_PinCode&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PromptResponse.pinCode(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PromptResponse_PinCodeCopyWith<$Res> implements $PromptResponseCopyWith<$Res> {
  factory $PromptResponse_PinCodeCopyWith(PromptResponse_PinCode value, $Res Function(PromptResponse_PinCode) _then) = _$PromptResponse_PinCodeCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$PromptResponse_PinCodeCopyWithImpl<$Res>
    implements $PromptResponse_PinCodeCopyWith<$Res> {
  _$PromptResponse_PinCodeCopyWithImpl(this._self, this._then);

  final PromptResponse_PinCode _self;
  final $Res Function(PromptResponse_PinCode) _then;

/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PromptResponse_PinCode(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PromptResponse_Passkey extends PromptResponse {
  const PromptResponse_Passkey(this.field0): super._();
  

 final  int field0;

/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptResponse_PasskeyCopyWith<PromptResponse_Passkey> get copyWith => _$PromptResponse_PasskeyCopyWithImpl<PromptResponse_Passkey>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptResponse_Passkey&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'PromptResponse.passkey(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $PromptResponse_PasskeyCopyWith<$Res> implements $PromptResponseCopyWith<$Res> {
  factory $PromptResponse_PasskeyCopyWith(PromptResponse_Passkey value, $Res Function(PromptResponse_Passkey) _then) = _$PromptResponse_PasskeyCopyWithImpl;
@useResult
$Res call({
 int field0
});




}
/// @nodoc
class _$PromptResponse_PasskeyCopyWithImpl<$Res>
    implements $PromptResponse_PasskeyCopyWith<$Res> {
  _$PromptResponse_PasskeyCopyWithImpl(this._self, this._then);

  final PromptResponse_Passkey _self;
  final $Res Function(PromptResponse_Passkey) _then;

/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(PromptResponse_Passkey(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class PromptResponse_Accept extends PromptResponse {
  const PromptResponse_Accept(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptResponse_Accept);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PromptResponse.accept()';
}


}




/// @nodoc


class PromptResponse_Deny extends PromptResponse {
  const PromptResponse_Deny(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptResponse_Deny);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PromptResponse.deny()';
}


}




/// @nodoc


class PromptResponse_Cancel extends PromptResponse {
  const PromptResponse_Cancel(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptResponse_Cancel);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PromptResponse.cancel()';
}


}




// dart format on

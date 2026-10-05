// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tray.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TrayActionOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayActionOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayActionOutcome()';
}


}

/// @nodoc
class $TrayActionOutcomeCopyWith<$Res>  {
$TrayActionOutcomeCopyWith(TrayActionOutcome _, $Res Function(TrayActionOutcome) __);
}


/// Adds pattern-matching-related methods to [TrayActionOutcome].
extension TrayActionOutcomePatterns on TrayActionOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TrayActionOutcome_Executed value)?  executed,TResult Function( TrayActionOutcome_Unsupported value)?  unsupported,TResult Function( TrayActionOutcome_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TrayActionOutcome_Executed() when executed != null:
return executed(_that);case TrayActionOutcome_Unsupported() when unsupported != null:
return unsupported(_that);case TrayActionOutcome_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TrayActionOutcome_Executed value)  executed,required TResult Function( TrayActionOutcome_Unsupported value)  unsupported,required TResult Function( TrayActionOutcome_Failed value)  failed,}){
final _that = this;
switch (_that) {
case TrayActionOutcome_Executed():
return executed(_that);case TrayActionOutcome_Unsupported():
return unsupported(_that);case TrayActionOutcome_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TrayActionOutcome_Executed value)?  executed,TResult? Function( TrayActionOutcome_Unsupported value)?  unsupported,TResult? Function( TrayActionOutcome_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case TrayActionOutcome_Executed() when executed != null:
return executed(_that);case TrayActionOutcome_Unsupported() when unsupported != null:
return unsupported(_that);case TrayActionOutcome_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  executed,TResult Function()?  unsupported,TResult Function( String reason)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TrayActionOutcome_Executed() when executed != null:
return executed();case TrayActionOutcome_Unsupported() when unsupported != null:
return unsupported();case TrayActionOutcome_Failed() when failed != null:
return failed(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  executed,required TResult Function()  unsupported,required TResult Function( String reason)  failed,}) {final _that = this;
switch (_that) {
case TrayActionOutcome_Executed():
return executed();case TrayActionOutcome_Unsupported():
return unsupported();case TrayActionOutcome_Failed():
return failed(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  executed,TResult? Function()?  unsupported,TResult? Function( String reason)?  failed,}) {final _that = this;
switch (_that) {
case TrayActionOutcome_Executed() when executed != null:
return executed();case TrayActionOutcome_Unsupported() when unsupported != null:
return unsupported();case TrayActionOutcome_Failed() when failed != null:
return failed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class TrayActionOutcome_Executed extends TrayActionOutcome {
  const TrayActionOutcome_Executed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayActionOutcome_Executed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayActionOutcome.executed()';
}


}




/// @nodoc


class TrayActionOutcome_Unsupported extends TrayActionOutcome {
  const TrayActionOutcome_Unsupported(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayActionOutcome_Unsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayActionOutcome.unsupported()';
}


}




/// @nodoc


class TrayActionOutcome_Failed extends TrayActionOutcome {
  const TrayActionOutcome_Failed({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of TrayActionOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrayActionOutcome_FailedCopyWith<TrayActionOutcome_Failed> get copyWith => _$TrayActionOutcome_FailedCopyWithImpl<TrayActionOutcome_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayActionOutcome_Failed&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'TrayActionOutcome.failed(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $TrayActionOutcome_FailedCopyWith<$Res> implements $TrayActionOutcomeCopyWith<$Res> {
  factory $TrayActionOutcome_FailedCopyWith(TrayActionOutcome_Failed value, $Res Function(TrayActionOutcome_Failed) _then) = _$TrayActionOutcome_FailedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$TrayActionOutcome_FailedCopyWithImpl<$Res>
    implements $TrayActionOutcome_FailedCopyWith<$Res> {
  _$TrayActionOutcome_FailedCopyWithImpl(this._self, this._then);

  final TrayActionOutcome_Failed _self;
  final $Res Function(TrayActionOutcome_Failed) _then;

/// Create a copy of TrayActionOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(TrayActionOutcome_Failed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on

// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tray_menu_service.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TrayMenuSelection {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayMenuSelection);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayMenuSelection()';
}


}

/// @nodoc
class $TrayMenuSelectionCopyWith<$Res>  {
$TrayMenuSelectionCopyWith(TrayMenuSelection _, $Res Function(TrayMenuSelection) __);
}


/// Adds pattern-matching-related methods to [TrayMenuSelection].
extension TrayMenuSelectionPatterns on TrayMenuSelection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TrayMenuSelection_Remote value)?  remote,TResult Function( TrayMenuSelection_Secondary value)?  secondary,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TrayMenuSelection_Remote() when remote != null:
return remote(_that);case TrayMenuSelection_Secondary() when secondary != null:
return secondary(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TrayMenuSelection_Remote value)  remote,required TResult Function( TrayMenuSelection_Secondary value)  secondary,}){
final _that = this;
switch (_that) {
case TrayMenuSelection_Remote():
return remote(_that);case TrayMenuSelection_Secondary():
return secondary(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TrayMenuSelection_Remote value)?  remote,TResult? Function( TrayMenuSelection_Secondary value)?  secondary,}){
final _that = this;
switch (_that) {
case TrayMenuSelection_Remote() when remote != null:
return remote(_that);case TrayMenuSelection_Secondary() when secondary != null:
return secondary(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int id)?  remote,TResult Function()?  secondary,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TrayMenuSelection_Remote() when remote != null:
return remote(_that.id);case TrayMenuSelection_Secondary() when secondary != null:
return secondary();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int id)  remote,required TResult Function()  secondary,}) {final _that = this;
switch (_that) {
case TrayMenuSelection_Remote():
return remote(_that.id);case TrayMenuSelection_Secondary():
return secondary();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int id)?  remote,TResult? Function()?  secondary,}) {final _that = this;
switch (_that) {
case TrayMenuSelection_Remote() when remote != null:
return remote(_that.id);case TrayMenuSelection_Secondary() when secondary != null:
return secondary();case _:
  return null;

}
}

}

/// @nodoc


class TrayMenuSelection_Remote extends TrayMenuSelection {
  const TrayMenuSelection_Remote({required this.id}): super._();
  

 final  int id;

/// Create a copy of TrayMenuSelection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrayMenuSelection_RemoteCopyWith<TrayMenuSelection_Remote> get copyWith => _$TrayMenuSelection_RemoteCopyWithImpl<TrayMenuSelection_Remote>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayMenuSelection_Remote&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode => Object.hash(runtimeType,id);

@override
String toString() {
  return 'TrayMenuSelection.remote(id: $id)';
}


}

/// @nodoc
abstract mixin class $TrayMenuSelection_RemoteCopyWith<$Res> implements $TrayMenuSelectionCopyWith<$Res> {
  factory $TrayMenuSelection_RemoteCopyWith(TrayMenuSelection_Remote value, $Res Function(TrayMenuSelection_Remote) _then) = _$TrayMenuSelection_RemoteCopyWithImpl;
@useResult
$Res call({
 int id
});




}
/// @nodoc
class _$TrayMenuSelection_RemoteCopyWithImpl<$Res>
    implements $TrayMenuSelection_RemoteCopyWith<$Res> {
  _$TrayMenuSelection_RemoteCopyWithImpl(this._self, this._then);

  final TrayMenuSelection_Remote _self;
  final $Res Function(TrayMenuSelection_Remote) _then;

/// Create a copy of TrayMenuSelection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(TrayMenuSelection_Remote(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TrayMenuSelection_Secondary extends TrayMenuSelection {
  const TrayMenuSelection_Secondary(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayMenuSelection_Secondary);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayMenuSelection.secondary()';
}


}




/// @nodoc
mixin _$TrayMenuUpdate {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayMenuUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayMenuUpdate()';
}


}

/// @nodoc
class $TrayMenuUpdateCopyWith<$Res>  {
$TrayMenuUpdateCopyWith(TrayMenuUpdate _, $Res Function(TrayMenuUpdate) __);
}


/// Adds pattern-matching-related methods to [TrayMenuUpdate].
extension TrayMenuUpdatePatterns on TrayMenuUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TrayMenuUpdate_Unchanged value)?  unchanged,TResult Function( TrayMenuUpdate_Updated value)?  updated,TResult Function( TrayMenuUpdate_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TrayMenuUpdate_Unchanged() when unchanged != null:
return unchanged(_that);case TrayMenuUpdate_Updated() when updated != null:
return updated(_that);case TrayMenuUpdate_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TrayMenuUpdate_Unchanged value)  unchanged,required TResult Function( TrayMenuUpdate_Updated value)  updated,required TResult Function( TrayMenuUpdate_Closed value)  closed,}){
final _that = this;
switch (_that) {
case TrayMenuUpdate_Unchanged():
return unchanged(_that);case TrayMenuUpdate_Updated():
return updated(_that);case TrayMenuUpdate_Closed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TrayMenuUpdate_Unchanged value)?  unchanged,TResult? Function( TrayMenuUpdate_Updated value)?  updated,TResult? Function( TrayMenuUpdate_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case TrayMenuUpdate_Unchanged() when unchanged != null:
return unchanged(_that);case TrayMenuUpdate_Updated() when updated != null:
return updated(_that);case TrayMenuUpdate_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( TrayMenuSnapshot snapshot)?  updated,TResult Function()?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TrayMenuUpdate_Unchanged() when unchanged != null:
return unchanged();case TrayMenuUpdate_Updated() when updated != null:
return updated(_that.snapshot);case TrayMenuUpdate_Closed() when closed != null:
return closed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( TrayMenuSnapshot snapshot)  updated,required TResult Function()  closed,}) {final _that = this;
switch (_that) {
case TrayMenuUpdate_Unchanged():
return unchanged();case TrayMenuUpdate_Updated():
return updated(_that.snapshot);case TrayMenuUpdate_Closed():
return closed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( TrayMenuSnapshot snapshot)?  updated,TResult? Function()?  closed,}) {final _that = this;
switch (_that) {
case TrayMenuUpdate_Unchanged() when unchanged != null:
return unchanged();case TrayMenuUpdate_Updated() when updated != null:
return updated(_that.snapshot);case TrayMenuUpdate_Closed() when closed != null:
return closed();case _:
  return null;

}
}

}

/// @nodoc


class TrayMenuUpdate_Unchanged extends TrayMenuUpdate {
  const TrayMenuUpdate_Unchanged(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayMenuUpdate_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayMenuUpdate.unchanged()';
}


}




/// @nodoc


class TrayMenuUpdate_Updated extends TrayMenuUpdate {
  const TrayMenuUpdate_Updated({required this.snapshot}): super._();
  

 final  TrayMenuSnapshot snapshot;

/// Create a copy of TrayMenuUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TrayMenuUpdate_UpdatedCopyWith<TrayMenuUpdate_Updated> get copyWith => _$TrayMenuUpdate_UpdatedCopyWithImpl<TrayMenuUpdate_Updated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayMenuUpdate_Updated&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode => Object.hash(runtimeType,snapshot);

@override
String toString() {
  return 'TrayMenuUpdate.updated(snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class $TrayMenuUpdate_UpdatedCopyWith<$Res> implements $TrayMenuUpdateCopyWith<$Res> {
  factory $TrayMenuUpdate_UpdatedCopyWith(TrayMenuUpdate_Updated value, $Res Function(TrayMenuUpdate_Updated) _then) = _$TrayMenuUpdate_UpdatedCopyWithImpl;
@useResult
$Res call({
 TrayMenuSnapshot snapshot
});




}
/// @nodoc
class _$TrayMenuUpdate_UpdatedCopyWithImpl<$Res>
    implements $TrayMenuUpdate_UpdatedCopyWith<$Res> {
  _$TrayMenuUpdate_UpdatedCopyWithImpl(this._self, this._then);

  final TrayMenuUpdate_Updated _self;
  final $Res Function(TrayMenuUpdate_Updated) _then;

/// Create a copy of TrayMenuUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? snapshot = null,}) {
  return _then(TrayMenuUpdate_Updated(
snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as TrayMenuSnapshot,
  ));
}


}

/// @nodoc


class TrayMenuUpdate_Closed extends TrayMenuUpdate {
  const TrayMenuUpdate_Closed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrayMenuUpdate_Closed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrayMenuUpdate.closed()';
}


}




// dart format on

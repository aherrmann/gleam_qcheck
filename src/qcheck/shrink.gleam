import gleam/iterator.{type Iterator}
import gleam/option.{type Option, None, Some}
import qcheck/tree.{type Tree}

fn int_half_difference(x, y) {
  { x / 2 } - { y / 2 }
}

fn int_shrink_step(x x, current_shrink current_shrink) {
  case x == current_shrink {
    True -> iterator.Done
    False -> {
      let half_difference = int_half_difference(x, current_shrink)

      case half_difference == 0 {
        True -> {
          iterator.Next(current_shrink, x)
        }
        False -> {
          iterator.Next(current_shrink, current_shrink + half_difference)
        }
      }
    }
  }
}

pub fn int_towards(
  destination destination: Int,
) -> fn(Int) -> iterator.Iterator(Int) {
  fn(x) {
    iterator.unfold(destination, fn(current_shrink) {
      int_shrink_step(x: x, current_shrink: current_shrink)
    })
  }
}

pub fn int_towards_zero() -> fn(Int) -> iterator.Iterator(Int) {
  int_towards(destination: 0)
}

fn do_filter_map(
  it: iterator.Iterator(a),
  f: fn(a) -> Option(b),
) -> iterator.Step(b, iterator.Iterator(a)) {
  case iterator.step(it) {
    iterator.Done -> iterator.Done
    iterator.Next(x, it) -> {
      case f(x) {
        None -> do_filter_map(it, f)
        Some(y) -> iterator.Next(y, it)
      }
    }
  }
}

fn filter_map(
  it: iterator.Iterator(a),
  f: fn(a) -> Option(b),
) -> iterator.Iterator(b) {
  iterator.unfold(it, do_filter_map(_, f))
}

// Custom type for readibility.
type RunPropertyResult {
  RunPropertyOk
  RunPropertyFail
}

// See QCheck2.run_law for why we bother with this seemingly pointless thing.
fn do_run_property(property, value, max_retries, i) {
  case i < max_retries {
    True -> {
      case property(value) {
        True -> do_run_property(property, value, max_retries, i + 1)
        False -> RunPropertyFail
      }
    }
    False -> RunPropertyOk
  }
}

// See QCheck2.run_law for why we bother with this seemingly pointless thing.
fn do_run_property_result(property, value, max_retries, i) {
  case i < max_retries {
    True -> {
      case property(value) {
        Ok(_) -> do_run_property_result(property, value, max_retries, i + 1)
        // TODO: return this error
        Error(_error) -> RunPropertyFail
      }
    }
    False -> RunPropertyOk
  }
}

fn run_property(property, value, max_retries) -> RunPropertyResult {
  do_run_property(property, value, max_retries, 0)
}

fn run_property_result(property, value, max_retries) -> RunPropertyResult {
  do_run_property_result(property, value, max_retries, 0)
}

pub fn shrink(
  tree: Tree(a),
  property: fn(a) -> Bool,
  run_property_max_retries run_property_max_retries: Int,
) -> a {
  let tree.Tree(original_failing_value, shrinks) = tree

  let result =
    shrinks
    |> filter_map(fn(tree) {
      let tree.Tree(value, _) = tree

      case run_property(property, value, run_property_max_retries) {
        RunPropertyOk -> None
        RunPropertyFail -> Some(tree)
      }
    })
    |> iterator.first

  case result {
    // Error means no head here.
    Error(Nil) -> original_failing_value
    // We have a head, that means we had a fail in one of the shrinks.
    Ok(next_tree) -> shrink(next_tree, property, run_property_max_retries)
  }
}

pub fn shrink_result(
  tree: Tree(a),
  property: fn(a) -> Result(b, error),
  run_property_max_retries run_property_max_retries: Int,
) -> a {
  let tree.Tree(original_failing_value, shrinks) = tree

  let result =
    shrinks
    |> filter_map(fn(tree) {
      let tree.Tree(value, _) = tree

      case run_property_result(property, value, run_property_max_retries) {
        RunPropertyOk -> None
        RunPropertyFail -> Some(tree)
      }
    })
    |> iterator.first

  case result {
    // Error means no head here.
    Error(Nil) -> original_failing_value
    // We have a head, that means we had a fail in one of the shrinks.
    Ok(next_tree) ->
      shrink_result(next_tree, property, run_property_max_retries)
  }
}

/// The `atomic` shrinker treats types as atomic, and never attempts to produce
/// smaller values.
pub fn atomic() -> fn(a) -> Iterator(a) {
  fn(_) { iterator.empty() }
}
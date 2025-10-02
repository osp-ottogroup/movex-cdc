<template>
  <b-modal :active="show" @close="$emit('close')">
    <div class="modal-card" style="width: 100%">
      <header class="modal-card-head">
        <p class="modal-card-title">Edit Column Expression</p>
        <button class="delete" @click="$emit('close')"></button>
      </header>
      <section class="modal-card-body">
        <b-field label="SQL Expression">
          <b-input v-model="localExpression.sql" type="textarea" rows="6"
                   placeholder="SQL statement which returns a single named column with a well formatted JSON object or JSON array of objects.
e.g.:
SELECT JSON_OBJECT('key1' VALUE col1, 'key2' VALUE col2) result FROM tab WHERE ID = :new.tab_id
or
SELECT '[ '||LISTAGG(JSON_OBJECT('Name' VALUE Name), ', ')||' ]' FROM tab WHERE Ref_ID = :new.ID
"
          />
        </b-field>
        <b-field label="Info">
          <b-input type="textarea" rows="1" v-model="localExpression.info" />
        </b-field>
      </section>
      <footer class="modal-card-foot">
        <b-button type="is-primary" @click="onSave">Save</b-button>
        <b-button type="is-danger" @click="onRemove" v-if="localExpression.id">Remove</b-button>
        <b-button @click="$emit('close')">Cancel</b-button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
export default {
  name: 'EditColumnExpressionModal',
  props: {
    show: Boolean,
    expression: Object,
  },
  data() {
    return {
      localExpression: { ...this.expression },
    };
  },
  watch: {
    expression(newVal) {
      this.localExpression = { ...newVal };
    },
  },
  methods: {
    onSave() {
      this.$emit('save', this.localExpression);
    },
    onRemove() {
      this.$emit('remove', this.localExpression);
    },
  },
};
</script>
